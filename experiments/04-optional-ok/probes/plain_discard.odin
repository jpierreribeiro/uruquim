package plain_discard

plain_extractor :: proc() -> (int, bool) {
	return 42, true
}

main :: proc() {
	value := plain_extractor()
	_ = value
}
