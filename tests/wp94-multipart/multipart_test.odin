// WP94 — the streaming multipart parser, boundary-correct across every
// fragmentation point, with the buffered parser's grammar as its oracle.
//
// The decisive property: feeding the SAME body one byte at a time, in two
// halves, or whole must produce identical parts — a delimiter split across
// feeds is still matched. File parts land on the spool (bytes verified from
// disk); field values stay in memory. A part is a file because it carries
// `filename`, never its content type.
package test_wp94_multipart

import "core:os"
import "core:strings"
import "core:testing"
import ingest "uruquim:web/internal/ingest"

SPOOL_DIR :: "/tmp/uruquim-wp94-mp"

BOUNDARY :: "----uruquim9zX"

GOOD :: "--" + BOUNDARY + "\r\n" +
	"Content-Disposition: form-data; name=\"title\"\r\n" +
	"\r\n" +
	"a report\r\n" +
	"--" + BOUNDARY + "\r\n" +
	"Content-Disposition: form-data; name=\"doc\"; filename=\"notes.txt\"\r\n" +
	"Content-Type: text/plain\r\n" +
	"\r\n" +
	"hello file contents that are long enough to span a chunk boundary somewhere\r\n" +
	"--" + BOUNDARY + "--"

@(private)
cfg :: proc() -> ingest.Spool_Config {
	if os.make_directory(SPOOL_DIR) != nil && !os.exists(SPOOL_DIR) {
		return ingest.Spool_Config{}
	}
	return ingest.Spool_Config {
		dir               = SPOOL_DIR,
		per_upload_quota  = 1 << 20,
		process_quota     = 8 << 20,
		max_concurrent    = 4,
		memory_prefix_max = 64 * 1024,
	}
}

// parse_in_chunks feeds `body` in slices of `step` bytes (step<=0 means whole).
@(private)
parse_in_chunks :: proc(a: ^ingest.Admission, p: ^ingest.MP_Parser, body: string, step: int) -> ingest.Ingest_Result {
	ok := ingest.mp_init(p, a, BOUNDARY)
	if !ok {return .Refused_Admission}
	bytes := transmute([]u8)body
	if step <= 0 {
		if res := ingest.mp_feed(p, bytes); res != .Ready {return res}
	} else {
		i := 0
		for i < len(bytes) {
			end := min(i + step, len(bytes))
			if res := ingest.mp_feed(p, bytes[i:end]); res != .Ready {return res}
			i = end
		}
	}
	return ingest.mp_finish(p)
}

@(test)
wp94_a_field_and_a_file_parse_whole :: proc(t: ^testing.T) {
	a: ingest.Admission
	testing.expect(t, ingest.admission_init(&a, cfg()))
	defer ingest.admission_destroy(&a)
	p: ingest.MP_Parser
	res := parse_in_chunks(&a, &p, GOOD, 0)
	defer ingest.mp_destroy(&p)
	testing.expect_value(t, res, ingest.Ingest_Result.Ready)
	testing.expect_value(t, len(p.parts), 2)

	title := p.parts[0]
	testing.expect_value(t, title.field, "title")
	testing.expect(t, !title.is_file)
	testing.expect_value(t, string(title.value), "a report")

	doc := p.parts[1]
	testing.expect_value(t, doc.field, "doc")
	testing.expect(t, doc.is_file, "a part with filename is a file")
	testing.expect_value(t, doc.filename, "notes.txt")
	testing.expect_value(t, doc.content_type, "text/plain")
	// The file bytes are on the spool, not in memory — read them back.
	data, err := os.read_entire_file_from_path(ingest.spool_path(&doc.spool), context.allocator)
	testing.expect(t, err == nil, "the spooled file must be readable")
	if err == nil {
		testing.expect_value(t, string(data), "hello file contents that are long enough to span a chunk boundary somewhere")
		delete(data)
	}
}

@(test)
wp94_every_fragmentation_point_yields_the_same_parts :: proc(t: ^testing.T) {
	// The property that matters: no chunk size changes the result. Steps of 1,
	// 2, 3, 5, 7, 13 land delimiters and CRLFs at every offset relative to a
	// chunk edge.
	for step in ([]int{1, 2, 3, 5, 7, 13, 64}) {
		a: ingest.Admission
		testing.expect(t, ingest.admission_init(&a, cfg()))
		p: ingest.MP_Parser
		res := parse_in_chunks(&a, &p, GOOD, step)
		ok := res == .Ready && len(p.parts) == 2 &&
			p.parts[0].field == "title" && string(p.parts[0].value) == "a report" &&
			p.parts[1].field == "doc" && p.parts[1].is_file &&
			p.parts[1].filename == "notes.txt"
		if ok {
			data, err := os.read_entire_file_from_path(ingest.spool_path(&p.parts[1].spool), context.allocator)
			ok = err == nil && string(data) == "hello file contents that are long enough to span a chunk boundary somewhere"
			if err == nil {delete(data)}
		}
		testing.expectf(t, ok, "fragmentation step %d must yield identical parts", step)
		ingest.mp_destroy(&p)
		ingest.admission_destroy(&a)
	}
}

@(test)
wp94_the_filename_is_never_a_path_the_parser_opens :: proc(t: ^testing.T) {
	// A traversal filename is recorded as metadata; the spool name is generated
	// and lives under the designated dir, so no file escapes.
	body := "--" + BOUNDARY + "\r\n" +
		"Content-Disposition: form-data; name=\"doc\"; filename=\"../../etc/passwd\"\r\n" +
		"\r\n" +
		"x\r\n" +
		"--" + BOUNDARY + "--"
	a: ingest.Admission
	testing.expect(t, ingest.admission_init(&a, cfg()))
	defer ingest.admission_destroy(&a)
	p: ingest.MP_Parser
	res := parse_in_chunks(&a, &p, body, 1)
	defer ingest.mp_destroy(&p)
	testing.expect_value(t, res, ingest.Ingest_Result.Ready)
	testing.expect_value(t, len(p.parts), 1)
	testing.expect_value(t, p.parts[0].filename, "../../etc/passwd") // recorded verbatim
	path := ingest.spool_path(&p.parts[0].spool)
	testing.expect(t, strings.has_prefix(path, SPOOL_DIR + "/uruquim-spool-"), "the file lives at a generated spool name, never the client path")
}

@(test)
wp94_a_truncated_body_fails :: proc(t: ^testing.T) {
	truncated := "--" + BOUNDARY + "\r\n" +
		"Content-Disposition: form-data; name=\"x\"\r\n" +
		"\r\n" +
		"no closing delimiter here"
	a: ingest.Admission
	testing.expect(t, ingest.admission_init(&a, cfg()))
	defer ingest.admission_destroy(&a)
	p: ingest.MP_Parser
	res := parse_in_chunks(&a, &p, truncated, 3)
	defer ingest.mp_destroy(&p)
	testing.expect(t, res != .Ready, "a body with no closing delimiter must not report Ready")
}

@(test)
wp94_persist_transfers_the_file_out_of_the_spool :: proc(t: ^testing.T) {
	a: ingest.Admission
	testing.expect(t, ingest.admission_init(&a, cfg()))
	defer ingest.admission_destroy(&a)
	p: ingest.MP_Parser
	res := parse_in_chunks(&a, &p, GOOD, 7)
	testing.expect_value(t, res, ingest.Ingest_Result.Ready)
	testing.expect_value(t, len(p.parts), 2)

	dest := SPOOL_DIR + "/persisted-notes.txt"
	testing.expect(t, ingest.persist(&p.parts[1].spool, dest), "a Ready file part must persist")
	defer _ = os.remove(dest)
	// mp_destroy now cleans everything; the persisted file must survive it.
	ingest.mp_destroy(&p)
	ingest.admission_destroy(&a)
	testing.expect(t, os.exists(dest), "the persisted file survives parser teardown")
}
