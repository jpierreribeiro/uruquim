// WP61 public-surface contract — static files, and mostly the files it refuses.
//
// TWO APPLICATION SYMBOLS: `static` and `Static_Options`.
//
// **THE REJECTIONS ARE THE FEATURE.** Serving a file is four lines; not serving
// `/etc/passwd`, `.env`, or a symlink out of the directory is the work. So the
// cases below are weighted accordingly: three prove it serves, and the rest
// prove what it will not.
//
// Every rejected path is answered 404 rather than 400, deliberately. A
// traversal attempt and a missing file are indistinguishable to the client,
// which is what stops the 404/400 difference from becoming a probe for what
// exists.
package test_wp61_public

import "core:log"
import "core:os"
import "core:strings"
import "core:testing"
import web "uruquim:web"

@(private = "file")
Quiet :: struct {
	inner: log.Logger,
}

@(private = "file")
quiet_logger_proc :: proc(
	data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {
	record := (^Quiet)(data)
	if level == .Error && strings.contains(text, "uruquim:") {
		return
	}
	if record.inner.procedure != nil {
		record.inner.procedure(record.inner.data, level, text, options, location)
	}
}

@(private = "file")
quiet_logger :: proc(record: ^Quiet) -> log.Logger {
	record.inner = context.logger
	return log.Logger {
		procedure = quiet_logger_proc,
		data = rawptr(record),
		lowest_level = .Debug,
		options = context.logger.options,
	}
}

// A directory laid out to make every rejection reachable:
//
//	<root>/public/app.js       the file that IS served
//	<root>/public/index.html   the mount-root file
//	<root>/public/.env         a dotfile, never served
//	<root>/secret.txt          OUTSIDE the mount, the traversal target
@(private = "file")
ROOT :: "tests/wp61-public-surface/fixture"
@(private = "file")
PUBLIC :: ROOT + "/public"

@(private = "file")
JS_BODY :: "console.log('hello')\n"

@(private = "file")
make_fixture :: proc() -> bool {
	if !os.exists(PUBLIC) {
		if os.make_directory(ROOT) != nil && !os.exists(ROOT) {
			return false
		}
		if os.make_directory(PUBLIC) != nil && !os.exists(PUBLIC) {
			return false
		}
	}
	_ = os.write_entire_file(PUBLIC + "/app.js", transmute([]u8)string(JS_BODY))
	_ = os.write_entire_file(PUBLIC + "/index.html", transmute([]u8)string("<h1>home</h1>"))
	_ = os.write_entire_file(PUBLIC + "/.env", transmute([]u8)string("SECRET=hunter2"))
	_ = os.write_entire_file(ROOT + "/secret.txt", transmute([]u8)string("do not serve me"))
	return os.exists(PUBLIC + "/app.js")
}

@(private = "file")
route_handler :: proc(ctx: ^web.Context) {
	web.text(ctx, .OK, "from a route")
}

@(private = "file")
mounted_app :: proc(a: ^web.App, o := web.Static_Options{}) {
	a^ = web.app()
	web.static(a, "/assets", PUBLIC, o)
	web.get(a, "/ping", route_handler)
}

@(private = "file")
header_value :: proc(res: web.Recorded_Response, name: string) -> (string, bool) {
	for h in res.headers {
		colon := strings.index_byte(h, ':')
		if colon < 0 {
			continue
		}
		if strings.equal_fold(strings.trim_space(h[:colon]), name) {
			return strings.trim_space(h[colon + 1:]), true
		}
	}
	return "", false
}

// The signatures, pinned by assignment.
@(test)
wp61_the_signatures_are_pinned :: proc(t: ^testing.T) {
	pinned: proc(a: ^web.App, prefix: string, dir: string, o: web.Static_Options) = web.static
	testing.expect(t, pinned != nil, "static must take an App, a prefix, a directory and options")

	o := web.Static_Options {
		max_file_size = 1024,
		index         = "index.html",
	}
	testing.expect_value(t, o.max_file_size, 1024)
	testing.expect_value(t, o.index, "index.html")
}

// It serves, with the type the extension implies.
@(test)
wp61_a_file_is_served_with_its_content_type :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "the fixture directory could not be created")
		return
	}
	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	res := web.test_request(&app, .GET, "/assets/app.js")
	testing.expect_value(t, res.status, web.Status.OK)
	testing.expect_value(t, res.body, JS_BODY)

	ct, has_ct := header_value(res, "Content-Type")
	testing.expect(t, has_ct, "a served file must carry a Content-Type")
	testing.expect(
		t,
		strings.has_prefix(ct, "text/javascript"),
		"a .js file must be text/javascript, not octet-stream",
	)

	_, has_etag := header_value(res, "ETag")
	testing.expect(t, has_etag, "a served file must carry an ETag, which is what makes 304 possible")
}

// The mount root serves the configured index, and 404s without one.
@(test)
wp61_the_index_is_served_at_the_mount_root :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	with: web.App
	mounted_app(&with, web.Static_Options{index = "index.html"})
	defer web.destroy(&with)

	res := web.test_request(&with, .GET, "/assets")
	testing.expect_value(t, res.status, web.Status.OK)
	testing.expect(t, strings.contains(res.body, "home"), "the index file must be served")

	without: web.App
	mounted_app(&without)
	defer web.destroy(&without)

	bare := web.test_request(&without, .GET, "/assets")
	testing.expect_value(t, bare.status, web.Status.Not_Found)
}

// A matching ETag answers 304 with no body — the whole point of sending one.
@(test)
wp61_a_matching_etag_answers_304 :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	first := web.test_request(&app, .GET, "/assets/app.js")
	etag, has_etag := header_value(first, "ETag")
	testing.expect(t, has_etag, "the first response must carry an ETag")

	line := strings.concatenate({"If-None-Match: ", etag}, context.temp_allocator)
	headers := [?]string{line}
	second := web.test_request(&app, .GET, "/assets/app.js", headers = headers[:])

	testing.expect_value(t, int(second.status), 304)
	testing.expect_value(t, len(second.body), 0)
}

// ---------------------------------------------------------------------------
// The rejections.
// ---------------------------------------------------------------------------

@(private = "file")
expect_refused :: proc(t: ^testing.T, app: ^web.App, path: string, why: string) {
	res := web.test_request(app, .GET, path)
	testing.expect_value(t, res.status, web.Status.Not_Found)
	testing.expect(
		t,
		!strings.contains(res.body, "do not serve me"),
		why,
	)
	testing.expect(t, !strings.contains(res.body, "hunter2"), why)
}

// **THE ONE THAT MATTERS MOST.** A traversal must not reach a file one
// directory up.
@(test)
wp61_traversal_is_refused :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	expect_refused(t, &app, "/assets/../secret.txt", "a ../ traversal must never escape the mount")
	expect_refused(t, &app, "/assets/a/../../secret.txt", "a nested traversal must never escape")
	expect_refused(t, &app, "/assets/..", "a bare .. must be refused")
}

// SECURITY BACKLOG F7 — a symlink at an INTERMEDIATE path segment is refused,
// not only a symlink at the final component. `web/static.odin` walks each
// intermediate segment with `os.lstat` and refuses any `.Symlink` before the
// final check; without this test that loop was unpinned (the whole static suite
// exercised only the final-component check and textual traversal). Reached
// through the ordinary request path, so a regression that removed the loop would
// serve a file the mount was never supposed to reach.
@(test)
wp61_a_symlink_in_an_intermediate_segment_is_refused :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	// A target that lives OUTSIDE the mount, reachable only by following a link.
	TARGET_DIR :: ROOT + "/linktarget"
	_ = os.make_directory(TARGET_DIR)
	_ = os.write_entire_file(TARGET_DIR + "/loot.txt", transmute([]u8)string("do not serve me"))

	// An intermediate symlink INSIDE the mount pointing at that outside dir.
	// `os.symlink` may report EEXIST from a prior run; the request result is what
	// the assertion turns on, so a pre-existing correct link is fine.
	_ = os.symlink(TARGET_DIR, PUBLIC + "/vialink")
	// And a final-component symlink to a file inside the mount, for the twin case.
	_ = os.symlink(PUBLIC + "/app.js", PUBLIC + "/app_link.js")

	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	// The intermediate segment `vialink` is a symlink: the lstat loop must refuse
	// the whole request before it ever reaches `loot.txt`.
	expect_refused(
		t,
		&app,
		"/assets/vialink/loot.txt",
		"a symlink at an intermediate segment must be refused, whatever it points at",
	)
	// The final-component symlink is refused too — even though it points INSIDE
	// the mount, because the policy refuses all links rather than resolving them.
	res := web.test_request(&app, .GET, "/assets/app_link.js")
	testing.expect_value(t, res.status, web.Status.Not_Found)
}

// Percent encoding is refused outright, because the framework never decodes the
// path (WP31a) — so `%2e%2e` would pass a textual `..` check untouched.
@(test)
wp61_percent_encoding_is_refused :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	expect_refused(t, &app, "/assets/%2e%2e/secret.txt", "an encoded traversal must be refused")
	expect_refused(t, &app, "/assets/%2f%2e%2e/secret.txt", "a double-encoded separator must be refused")
	// Even a harmless-looking encoded name is refused: the rule is textual and
	// has no exceptions, because an exception is where the bypass lives.
	expect_refused(t, &app, "/assets/app%2ejs", "any percent in a static path is refused")
}

// Dotfiles are exactly the files a directory should not serve.
@(test)
wp61_dotfiles_are_refused :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	expect_refused(t, &app, "/assets/.env", ".env must never be served")
}

// A backslash means a separator on one platform and a filename byte on another.
@(test)
wp61_backslash_and_empty_segments_are_refused :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	expect_refused(t, &app, "/assets/..\\secret.txt", "a backslash must be refused")
	expect_refused(t, &app, "/assets//app.js", "an empty interior segment must be refused")
	expect_refused(t, &app, "/assets/app.js/", "a trailing slash names a directory, not a file")
}

// A file above the cap is refused, because the response would be buffered whole.
@(test)
wp61_a_file_over_the_cap_is_refused :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	app: web.App
	mounted_app(&app, web.Static_Options{max_file_size = 4})
	defer web.destroy(&app)

	res := web.test_request(&app, .GET, "/assets/app.js")
	testing.expect_value(t, res.status, web.Status.Not_Found)
	testing.expect(
		t,
		!strings.contains(res.body, "console.log"),
		"a file above max_file_size must not be served: the response is buffered whole",
	)
}

// **THE PREFIX BOUNDARY BUG EVERY PREFIX ROUTER HAS SHIPPED ONCE.** `/assets`
// must not match `/assetsomething`.
@(test)
wp61_the_prefix_boundary_is_respected :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	res := web.test_request(&app, .GET, "/assetsomething")
	testing.expect_value(t, res.status, web.Status.Not_Found)

	// And a route outside the mount still works: mounting a directory must not
	// swallow the rest of the application.
	routed := web.test_request(&app, .GET, "/ping")
	testing.expect_value(t, routed.status, web.Status.OK)
	testing.expect_value(t, routed.body, "from a route")
}

// A POST under the mount is the router's business — a static mount answers GET
// and HEAD, so the 405 that names what the path supports must still happen.
@(test)
wp61_a_post_under_the_mount_is_not_swallowed :: proc(t: ^testing.T) {
	if !make_fixture() {
		testing.expect(t, false, "fixture")
		return
	}
	app: web.App
	mounted_app(&app)
	defer web.destroy(&app)

	res := web.test_request(&app, .POST, "/assets/app.js")
	testing.expect(
		t,
		res.status != web.Status.OK,
		"a POST must never be answered from the filesystem",
	)
}

// ---------------------------------------------------------------------------
// Fail-closed registration.
// ---------------------------------------------------------------------------

@(private = "file")
is_poisoned :: proc(a: ^web.App) -> bool {
	res := web.test_request(a, .GET, "/ping")
	return res.status == web.Status.Internal_Server_Error
}

@(test)
wp61_a_bad_mount_is_refused :: proc(t: ^testing.T) {
	quiet: Quiet
	context.logger = quiet_logger(&quiet)

	relative := web.app()
	defer web.destroy(&relative)
	web.get(&relative, "/ping", route_handler)
	web.static(&relative, "assets", PUBLIC)
	testing.expect(t, is_poisoned(&relative), "a prefix that is not absolute must be refused")

	trailing := web.app()
	defer web.destroy(&trailing)
	web.get(&trailing, "/ping", route_handler)
	web.static(&trailing, "/assets/", PUBLIC)
	testing.expect(t, is_poisoned(&trailing), "a prefix ending in a slash must be refused")

	empty := web.app()
	defer web.destroy(&empty)
	web.get(&empty, "/ping", route_handler)
	web.static(&empty, "/assets", "")
	testing.expect(t, is_poisoned(&empty), "an empty directory must be refused")
}
