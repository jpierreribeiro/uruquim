package main

Handler_Error :: struct { failed: bool }

handler_with_unnamed_result :: proc(ok: bool) -> Handler_Error {
	if !ok {
		return // Expected diagnostic: return value required.
	}
	return {}
}

main :: proc() {
	_ = handler_with_unnamed_result(false)
}
