// Streaming multipart parser — WP94's second component.
//
// It consumes `[]u8` chunks and NEVER reads a socket (ADR-033): the adapter
// feeds it whatever arrived. It is boundary-correct across EVERY fragmentation
// point — a delimiter split across two chunks is matched — because it carries
// at most `len(delimiter)+2` unconfirmed bytes between feeds. Field values and
// part headers stay in bounded memory (`memory_prefix_max`); file parts stream
// straight to the ingest spool, so a multi-gigabyte upload never occupies RAM
// proportional to its size (G7-9). A part is a FILE because it carries
// `filename`, never because of its content type — the same rule the buffered
// oracle enforces, which is this parser's compatibility reference.
//
// It trusts neither the filename nor the part Content-Type: the filename is
// metadata handed to the application, never a path the parser opens (the spool
// name is generated), and the content type is recorded, never acted on.
package uruquim_internal_ingest

import "core:strings"

MP_FIELD_MAX :: 64 * 1024 // hard ceiling on one field value / header block

MP_State :: enum u8 {
	Opening, // before the first delimiter
	After_Delim, // just past a delimiter: expect CRLF (another part) or -- (end)
	Headers, // accumulating the part header block
	Field, // accumulating a field value in memory
	File, // streaming a file part to the spool
	Done,
	Failed,
}

MP_Part :: struct {
	field:        string, // owned by the parser; valid until mp_destroy
	filename:     string,
	content_type: string,
	is_file:      bool,
	// For a field: the value bytes (owned). For a file: the owned spool. The
	// spool file is cleaned by mp_destroy unless the application persisted it.
	value:        []u8,
	spool:        Spool,
	has_spool:    bool,
	spool_bytes:  i64,
}

MP_Parser :: struct {
	admission:  ^Admission,
	delimiter:  string, // "--" + boundary, owned
	state:      MP_State,
	acc:        [dynamic]u8, // bounded accumulator for headers/field values
	carry:      [dynamic]u8, // unconfirmed file bytes (< len(delimiter)+2)
	cur:        MP_Part,
	spool:      Spool,
	spool_open: bool,
	parts:      [dynamic]MP_Part, // completed parts, in order
	fail_code:  Ingest_Result,
}

mp_init :: proc(p: ^MP_Parser, admission: ^Admission, boundary: string) -> bool {
	if len(boundary) == 0 {
		return false // an empty boundary matches everywhere (oracle rule)
	}
	p.admission = admission
	p.delimiter = strings.concatenate({"--", boundary})
	p.state = .Opening
	p.acc = make([dynamic]u8)
	p.carry = make([dynamic]u8)
	p.parts = make([dynamic]MP_Part)
	p.fail_code = .Ready
	return true
}

mp_destroy :: proc(p: ^MP_Parser) {
	if p.spool_open {
		cancel(&p.spool, .Cancelled_By_Drain)
		p.spool_open = false
	}
	for &part in p.parts {
		if len(part.value) > 0 {delete(part.value)}
		if len(part.field) > 0 {delete(part.field)}
		if len(part.filename) > 0 {delete(part.filename)}
		if len(part.content_type) > 0 {delete(part.content_type)}
		// Automatic cleanup: a Ready file the application never persisted is
		// deleted exactly once (§4.2). persist() left the spool terminal, so
		// cancel is then a safe no-op that touches no transferred file.
		if part.has_spool {cancel(&part.spool, .Cancelled_By_Drain)}
	}
	delete(p.parts)
	// An in-progress part (a body that failed after its headers parsed) owns
	// cloned strings too.
	if len(p.cur.field) > 0 {delete(p.cur.field)}
	if len(p.cur.filename) > 0 {delete(p.cur.filename)}
	if len(p.cur.content_type) > 0 {delete(p.cur.content_type)}
	delete(p.acc)
	delete(p.carry)
	delete(p.delimiter)
	p^ = MP_Parser{}
}

@(private)
mp_fail :: proc(p: ^MP_Parser, code: Ingest_Result) -> Ingest_Result {
	if p.spool_open {
		cancel(&p.spool, code)
		p.spool_open = false
	}
	p.state = .Failed
	p.fail_code = code
	return code
}

// mp_feed consumes one arriving chunk. It returns .Ready while more is
// expected, a terminal code on failure, or .Ready with state == .Done when the
// closing delimiter has been seen. The caller feeds until the body is
// exhausted, then calls mp_finish.
mp_feed :: proc(p: ^MP_Parser, chunk: []u8) -> Ingest_Result {
	if p.state == .Failed {return p.fail_code}
	if p.state == .Done {return .Ready}

	// File content is processed with a carry so a delimiter split across
	// feeds is still matched; everything else accumulates in bounded memory.
	data := chunk
	for len(data) > 0 || p.state == .File {
		switch p.state {
		case .Opening, .After_Delim, .Headers, .Field:
			if len(data) == 0 {return .Ready}
			// Append one byte at a time is simplest and the volume here is
			// bounded (headers/fields), so it is not a hot path.
			if len(p.acc) >= MP_FIELD_MAX {
				return mp_fail(p, .Quota_Exceeded)
			}
			append(&p.acc, data[0])
			data = data[1:]
			if res := mp_try_advance(p); res != .Ready {
				return res
			}
		case .File:
			if res := mp_feed_file(p, &data); res != .Ready {
				return res
			}
			if len(data) == 0 && p.state == .File {
				return .Ready
			}
		case .Done:
			return .Ready
		case .Failed:
			return p.fail_code
		}
	}
	return .Ready
}

// mp_try_advance inspects the accumulator after each byte for the structural
// tokens the current state waits on.
@(private)
mp_try_advance :: proc(p: ^MP_Parser) -> Ingest_Result {
	switch p.state {
	case .Opening:
		// Wait for the opening delimiter as a prefix.
		if len(p.acc) < len(p.delimiter) {
			// A mismatch as soon as it is unambiguous is a malformed body.
			if !bytes_prefix_compatible(p.acc[:], p.delimiter) {
				return mp_fail(p, .Disconnected)
			}
			return .Ready
		}
		if string(p.acc[:len(p.delimiter)]) != p.delimiter {
			return mp_fail(p, .Disconnected)
		}
		clear(&p.acc)
		p.state = .After_Delim
		return .Ready
	case .After_Delim:
		if len(p.acc) < 2 {return .Ready}
		two := string(p.acc[:2])
		if two == "--" {
			p.state = .Done
			clear(&p.acc)
			return .Ready
		}
		if two != "\r\n" {
			return mp_fail(p, .Disconnected)
		}
		clear(&p.acc)
		p.state = .Headers
		return .Ready
	case .Headers:
		// The header block ends at the first CRLFCRLF.
		if idx := bytes_index(p.acc[:], "\r\n\r\n"); idx >= 0 {
			if !mp_read_headers(p, string(p.acc[:idx])) {
				return mp_fail(p, .Disconnected)
			}
			clear(&p.acc)
			return mp_start_content(p)
		}
		return .Ready
	case .Field:
		// A field value ends at CRLF + delimiter. We hold the whole value in
		// bounded memory, so scan the accumulator for the terminator.
		term := mp_value_terminator(p, p.acc[:])
		if term >= 0 {
			mp_emit_field(p, p.acc[:term])
			// Re-seed the accumulator past the CRLF, at the delimiter, and
			// resume in After_Delim by consuming the delimiter.
			rest := p.acc[term + 2:] // skip the CRLF
			return mp_consume_delim_from_acc(p, rest)
		}
		return .Ready
	case .File, .Done, .Failed:
	}
	return .Ready
}

// mp_start_content decides field vs file from the parsed disposition and opens
// a spool for files.
@(private)
mp_start_content :: proc(p: ^MP_Parser) -> Ingest_Result {
	if len(p.cur.field) == 0 {
		return mp_fail(p, .Disconnected) // a nameless part is malformed (oracle)
	}
	if p.cur.is_file {
		if admit(p.admission) != .Ready {
			return mp_fail(p, .Refused_Admission)
		}
		if begin(p.admission, &p.spool) != .Ready {
			return mp_fail(p, .Disk_Full)
		}
		p.spool_open = true
		p.state = .File
		clear(&p.carry)
		return .Ready
	}
	p.state = .Field
	return .Ready
}

// mp_feed_file streams file bytes to the spool, holding back only the tail that
// could still be the start of the closing "\r\n" + delimiter.
@(private)
mp_feed_file :: proc(p: ^MP_Parser, data: ^[]u8) -> Ingest_Result {
	needle := mp_file_terminator_string(p) // "\r\n" + delimiter
	// Move all available bytes into carry, then flush everything that cannot
	// be part of a terminator prefix at the tail.
	for len(data^) > 0 {
		append(&p.carry, data^[0])
		data^ = data^[1:]
		// If carry now contains the full terminator, the file part ends.
		if idx := bytes_index(p.carry[:], needle); idx >= 0 {
			if idx > 0 {
				if res := mp_spool_write(p, p.carry[:idx]); res != .Ready {
					return res
				}
			}
			// Consume through the terminator; the delimiter is now behind us.
			consumed := idx + len(needle)
			leftover := make([]u8, len(p.carry) - consumed)
			copy(leftover, p.carry[consumed:])
			clear(&p.carry)
			mp_close_file(p)
			// The bytes after the delimiter re-enter as After_Delim input.
			p.state = .After_Delim
			if res := mp_reinject(p, leftover); res != .Ready {
				delete(leftover)
				return res
			}
			delete(leftover)
			return .Ready
		}
		// Flush the safe prefix: keep only the last (len(needle)-1) bytes,
		// which are all that could still begin a terminator.
		keep := len(needle) - 1
		if len(p.carry) > keep {
			flush := len(p.carry) - keep
			if res := mp_spool_write(p, p.carry[:flush]); res != .Ready {
				return res
			}
			remaining := make([]u8, keep)
			copy(remaining, p.carry[flush:])
			clear(&p.carry)
			append(&p.carry, ..remaining)
			delete(remaining)
		}
	}
	return .Ready
}

@(private)
mp_spool_write :: proc(p: ^MP_Parser, bytes: []u8) -> Ingest_Result {
	res := append_chunk(&p.spool, bytes)
	if res != .Ready {
		p.spool_open = false // append_chunk already cancelled on failure
		p.state = .Failed
		p.fail_code = res
	}
	return res
}

@(private)
mp_close_file :: proc(p: ^MP_Parser) {
	finish(&p.spool)
	part := p.cur
	part.spool = p.spool // ownership of the Ready spool transfers to the part
	part.has_spool = true
	part.spool_bytes = spooled_bytes(&p.spool)
	// The part's spool now holds the ^Admission pointer it needs for its own
	// eventual cancel/persist; re-home it so admission accounting stays right.
	part.spool.admission = p.admission
	append(&p.parts, part)
	p.spool = Spool{}
	p.spool_open = false // the file is Ready, owned by the emitted part
	p.cur = MP_Part{}
}

// mp_emit_field records a completed in-memory field value (a copy the parser
// owns), then resets for the next part.
@(private)
mp_emit_field :: proc(p: ^MP_Parser, value: []u8) {
	part := p.cur
	v := make([]u8, len(value))
	copy(v, value)
	part.value = v
	append(&p.parts, part)
	p.cur = MP_Part{}
}

// mp_finish is called once the body is exhausted. A well-formed body has
// reached .Done; anything else is a truncated/malformed body.
mp_finish :: proc(p: ^MP_Parser) -> Ingest_Result {
	if p.state == .Done {return .Ready}
	if p.state == .Failed {return p.fail_code}
	return mp_fail(p, .Disconnected)
}

// --- header parsing, mirroring the buffered oracle exactly -------------------

@(private)
mp_read_headers :: proc(p: ^MP_Parser, headers: string) -> bool {
	rest := headers
	for len(rest) > 0 {
		line := rest
		if crlf := strings.index(rest, "\r\n"); crlf >= 0 {
			line = rest[:crlf]
			rest = rest[crlf + 2:]
		} else {
			rest = ""
		}
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			return false
		}
		name := strings.trim_space(line[:colon])
		value := strings.trim_space(line[colon + 1:])
		if mp_fold_equal(name, "content-disposition") {
			if field, ok := mp_parameter(value, "name"); ok {
				p.cur.field = strings.clone(field)
			}
			if filename, ok := mp_parameter(value, "filename"); ok {
				p.cur.filename = strings.clone(filename)
				p.cur.is_file = true // presence of filename makes it a file
			}
		} else if mp_fold_equal(name, "content-type") {
			p.cur.content_type = strings.clone(value)
		}
	}
	return true
}

@(private)
mp_parameter :: proc(value: string, key: string) -> (string, bool) {
	needle := strings.concatenate({key, "=\""}, context.temp_allocator)
	at := strings.index(value, needle)
	if at < 0 {return "", false}
	rest := value[at + len(needle):]
	close := strings.index_byte(rest, '"')
	if close < 0 {return "", false}
	return rest[:close], true
}

@(private)
mp_fold_equal :: proc(a, b: string) -> bool {
	if len(a) != len(b) {return false}
	for i in 0 ..< len(a) {
		ca, cb := a[i], b[i]
		if ca >= 'A' && ca <= 'Z' {ca += 32}
		if cb >= 'A' && cb <= 'Z' {cb += 32}
		if ca != cb {return false}
	}
	return true
}

// --- small byte helpers ------------------------------------------------------

@(private)
mp_value_terminator :: proc(p: ^MP_Parser, acc: []u8) -> int {
	// A field value ends at CRLF immediately followed by the delimiter.
	needle := mp_file_terminator_string(p)
	return bytes_index(acc, needle)
}

@(private)
mp_file_terminator_string :: proc(p: ^MP_Parser) -> string {
	// "\r\n" + delimiter. Built once per call over the owned delimiter; the
	// concatenation lives in the temp allocator.
	return strings.concatenate({"\r\n", p.delimiter}, context.temp_allocator)
}

@(private)
mp_consume_delim_from_acc :: proc(p: ^MP_Parser, rest: []u8) -> Ingest_Result {
	// `rest` begins at the delimiter. Consume it and hand the tail back as
	// After_Delim input.
	if len(rest) < len(p.delimiter) {
		return mp_fail(p, .Disconnected)
	}
	if string(rest[:len(p.delimiter)]) != p.delimiter {
		return mp_fail(p, .Disconnected)
	}
	tail := make([]u8, len(rest) - len(p.delimiter))
	copy(tail, rest[len(p.delimiter):])
	clear(&p.acc)
	p.state = .After_Delim
	res := mp_reinject(p, tail)
	delete(tail)
	return res
}

// mp_reinject re-feeds already-buffered bytes into the state machine (used
// after a delimiter is consumed, when leftover bytes belong to the next part).
@(private)
mp_reinject :: proc(p: ^MP_Parser, data: []u8) -> Ingest_Result {
	for b in data {
		if p.state == .File {
			one := [1]u8{b}
			d := one[:]
			if res := mp_feed_file(p, &d); res != .Ready {return res}
			continue
		}
		if p.state == .Done || p.state == .Failed {
			return p.state == .Failed ? p.fail_code : .Ready
		}
		if len(p.acc) >= MP_FIELD_MAX {
			return mp_fail(p, .Quota_Exceeded)
		}
		append(&p.acc, b)
		if res := mp_try_advance(p); res != .Ready {return res}
	}
	return .Ready
}

@(private)
bytes_index :: proc(haystack: []u8, needle: string) -> int {
	return strings.index(string(haystack), needle)
}

// bytes_prefix_compatible reports whether `have` could still be a prefix of
// `want` — i.e. they agree on every byte `have` has.
@(private)
bytes_prefix_compatible :: proc(have: []u8, want: string) -> bool {
	if len(have) > len(want) {return false}
	return string(have) == want[:len(have)]
}
