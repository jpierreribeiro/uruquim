// Experiment 04 — optional-ok
// Question: is `#optional_ok` valid for the value-producing extractor shape,
// can the bool be discarded, what diagnostic appears, and how does it compare
// with the plain two-result form (risk for humans/LLMs)?
//
// THROWAWAY. Not imported by any product package.
package optional_ok

import "core:fmt"
import "core:strconv"

Context :: struct {
	params:    map[string]string,
	responded: bool,
}

// value-producing extractor with #optional_ok.
path_int :: proc(ctx: ^Context, name: string) -> (value: int, ok: bool) #optional_ok {
	raw, found := ctx.params[name]
	if !found {
		ctx.responded = true // real framework writes invalid_path_parameter
		return 0, false
	}
	v, parsed := strconv.parse_int(raw)
	if !parsed {
		ctx.responded = true
		return 0, false
	}
	return v, true
}

// plain two-result form WITHOUT the directive, for comparison.
query_int_plain :: proc(ctx: ^Context, name: string) -> (int, bool) {
	raw, found := ctx.params[name]
	if !found { return 0, false }
	v, parsed := strconv.parse_int(raw)
	return v, parsed
}

main :: proc() {
	ctx := Context{ params = make(map[string]string) }
	defer delete(ctx.params)
	ctx.params["id"] = "42"
	ctx.params["bad"] = "x"

	// canonical: check ok, then return.
	id, ok := path_int(&ctx, "id")
	fmt.printfln("checked   -> id=%d ok=%v", id, ok)

	// #optional_ok allows discarding the bool (single-result use). We show it
	// compiles, but the canonical HTTP rule is: ALWAYS check ok.
	just_id := path_int(&ctx, "id")
	fmt.printfln("discarded -> just_id=%d (ok discarded; allowed but discouraged)", just_id)

	// failure path still returns a usable zero value.
	missing, ok2 := path_int(&ctx, "nope")
	fmt.printfln("missing   -> v=%d ok=%v responded=%v", missing, ok2, ctx.responded)

	// plain form has NO #optional_ok: discarding the bool must be a COMPILE
	// ERROR (uncomment to record the intended-failure diagnostic).
	// p := query_int_plain(&ctx, "id")   // <- expected: error, 2 values -> 1
	_ = query_int_plain
}
