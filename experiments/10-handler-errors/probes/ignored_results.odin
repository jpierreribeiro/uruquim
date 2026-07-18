package main

Handler_Error :: struct { failed: bool }
Handler_Outcome :: struct { failed: bool }

json_b :: proc() -> Handler_Error {
	return {failed = true}
}

json_c :: proc() -> Handler_Outcome {
	return {failed = true}
}

handler_b_ignores_error :: proc() -> Handler_Error {
	json_b() // Compiles: the returned error can be silently discarded.
	return {}
}

handler_c_ignores_outcome :: proc() -> Handler_Outcome {
	json_c() // Compiles: the returned outcome can be silently discarded.
	return {}
}

main :: proc() {
	_ = handler_b_ignores_error()
	_ = handler_c_ignores_outcome()
}
