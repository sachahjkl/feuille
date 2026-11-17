package feuille

// The program's tests: the whole program, headless (no window of the system, no system dialog), on PDFs the tests
// write into their own folders. One interface at a time: -define:ODIN_TEST_THREADS=1 (feuilletool test does it).

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import host "gt:host"
import "gt:platform"
import "gt:testkit"
import session "gt:testkit/session"
import fixture "fixture"
import pdf "pdf"

@(private = "file")
BLUE  :: session.Color{0, 0, 255, 255}
@(private = "file")
RED   :: session.Color{255, 0, 0, 255}
@(private = "file")
WHITE :: session.Color{255, 255, 255, 255}

// The program on `path`, in a session that ends with the test.
@(private = "file")
start :: proc(t: ^testing.T, path: string, size := [2]int{700, 800}, loc := #caller_location) -> (s: ^session.Session, app: ^App) {
	context.allocator = runtime.heap_allocator()
	app = app_open({path = path, headless = true, size = size})
	if !testing.expect(t, app != nil, "feuille opens", loc = loc) { session.stop_test(t, "no application", loc) }
	testing.cleanup(t, proc(p: rawptr) { app_close((^App)(p)) }, app)
	s = session.attach(t, {win = app.main.win, state = &app.main.state, renderer = &app.shared.r, user = app, allocator = context.allocator,
		frame = proc(user: rawptr) { host.host_frame(&(^App)(user).main) }}, loc)
	return
}

// A PDF of the tests' writer, in the test's folder.
@(private = "file")
write_pdf :: proc(t: ^testing.T, name: string, o: fixture.Options) -> string {
	dir := testkit.temp_folder(t, "feuille")
	path := fmt.aprintf("%s/%s", dir, name, allocator = context.temp_allocator)
	testing.expect(t, os.write_entire_file(path, fixture.make_pdf(o, context.temp_allocator)) == nil, "the fixture is written")
	return path
}

// The pixel of the window at the point `at` of page `index` (at in the page's points, y up, as the fixture gives them).
@(private = "file")
page_pixel :: proc(s: ^session.Session, app: ^App, img: session.Image, index: int, at: [2]f32) -> session.Color {
	p := app.snapshot.pages[index]
	b := session.get(s, fmt.tprintf("page%d", p.id))
	w, h := b.rect.max.x - b.rect.min.x, b.rect.max.y - b.rect.min.y
	k := app.main.state.scale
	x := (b.rect.min.x + at.x / p.size.x * w) * k
	y := (b.rect.min.y + (1 - at.y / p.size.y) * h) * k
	return session.pixel(img, int(x), int(y))
}

@(private = "file")
centre :: proc(r: [4]f32) -> [2]f32 { return {r[0] + r[2] / 2, r[1] + r[3] / 2} }

// Every picture in view is there, and of the layer asked.
@(private = "file")
pictures_ready :: proc(s: ^session.Session, app: ^App) -> bool {
	if app.snapshot == nil || len(app.last_ask) == 0 { return false }
	for a in app.last_ask {
		shown, ok := app.pictures[a.id]
		if !ok || shown.size != a.size || shown.layer != a.layer { return false }
	}
	return true
}

// The day-one test, in the window: the blocked document asks its password, then opens with its layer hidden; Ctrl+L
// shows it.
@(test)
the_blocked_document_opens_masked_in_the_window :: proc(t: ^testing.T) {
	path := write_pdf(t, "blocked.pdf", {layer = true, password = "secret"})
	s, app := start(t, path)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.pending == .Locked }, "the password is asked")
	session.wait_box(s, "password")
	session.click(s, "password")
	session.type_text(s, "wrong")
	session.key(s, .Return)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.wrong }, "a wrong password is told")
	testing.expect(t, app.snapshot == nil, "nothing opens with a wrong password")

	session.type_text(s, "secret")
	session.key(s, .Return)
	session.wait_until(s, app, pictures_ready, "the page is drawn")
	testing.expect_value(t, len(app.snapshot.pages), 1)
	img := session.capture(s)
	testing.expect_value(t, page_pixel(s, app, img, 0, centre(fixture.BASE_RECT)), BLUE)
	testing.expect_value(t, page_pixel(s, app, img, 0, centre(fixture.FIELD_RECT)), WHITE)

	session.key(s, .L, {.Ctrl})
	testing.expect(t, app.layer, "Ctrl+L shows the layer")
	session.wait_until(s, app, pictures_ready, "the page is drawn again, with its layer")
	img = session.capture(s)
	testing.expect_value(t, page_pixel(s, app, img, 0, centre(fixture.FIELD_RECT)), RED)
	session.save_png(s, "layer.png")
}

@(test)
what_is_not_a_pdf_is_told :: proc(t: ^testing.T) {
	dir := testkit.temp_folder(t, "feuille")
	path := fmt.tprintf("%s/notes.pdf", dir)
	junk := "not a pdf at all"
	testing.expect(t, os.write_entire_file(path, transmute([]u8)junk) == nil)
	s, app := start(t, path)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.failure != .None }, "the failure is told")
	testing.expect_value(t, app.failure, pdf.Error.Format)
	session.wait_text(s, "notes.pdf cannot be opened")
}

// A long document builds only the pages near the view, and draws the ones in it.
@(test)
a_long_document_builds_the_pages_in_view :: proc(t: ^testing.T) {
	pages := make([]fixture.Page, 400, context.temp_allocator)
	for &p in pages { p = {size = {200, 280}} }
	path := write_pdf(t, "long.pdf", {pages = pages})
	s, app := start(t, path)
	session.wait_until(s, app, pictures_ready, "the first pages are drawn")
	testing.expect_value(t, len(app.snapshot.pages), 400)
	built := 0
	for p in app.snapshot.pages {
		if session.find(s, fmt.tprintf("page%d", p.id)) != nil { built += 1 }
	}
	testing.expect(t, built > 0 && built < 10, fmt.tprintf("a few pages built, not %d", built))
	testing.expect(t, len(app.last_ask) < 10, "a few pictures asked")
	session.save_png(s, "window.png")   // (build/session/: what the window showed, to look at)
}

// A PDF dropped on the window opens.
@(test)
a_dropped_pdf_opens :: proc(t: ^testing.T) {
	path := write_pdf(t, "dropped.pdf", {})
	s, app := start(t, "")
	session.wait_text(s, "Open a PDF")
	data: platform.Drag_Data
	append(&data.files, path)
	defer delete(data.files)
	platform.drop_inject(app.main.win, .Drop_Enter, {100, 100}, &data)
	platform.drop_inject(app.main.win, .Drop, {100, 100})
	session.wait_until(s, app, pictures_ready, "the dropped file is drawn")
	testing.expect_value(t, len(app.snapshot.pages), 1)
}
