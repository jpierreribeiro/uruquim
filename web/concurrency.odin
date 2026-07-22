// WP70 — the private publication boundary for concurrent serving.
package web
// uruquim:file application

import "core:sync"

@(private)
app_is_serving :: proc(a: ^App) -> bool {
	return sync.atomic_load(&a.private.serving) != 0
}

@(private)
app_has_dispatched :: proc(a: ^App) -> bool {
	return sync.atomic_load(&a.private.dispatched) != 0
}

@(private)
app_mark_dispatched :: proc(a: ^App) {
	sync.atomic_store(&a.private.dispatched, 1)
}

// app_prepare_serving completes every lazy App-lifetime structure before the
// transport can create a second lane, then publishes the immutable snapshot.
@(private)
app_prepare_serving :: proc(a: ^App) {
	if app_is_serving(a) {
		return
	}
	miss_chain_ensure(a)
	sync.atomic_store(&a.private.serving, 1)
}

// Late configuration must not poison the live snapshot: writing `poisoned`
// while lanes read it would merely replace one race with another. Refuse the
// mutation, report it, and leave the published App byte-identical.
@(private)
app_reject_late_configuration :: proc(a: ^App, loc := #caller_location) {
	framework_report(App, .Use_After_Route, loc)
	framework_observe_app(App, a, .Use_After_Route)
}
