package feuille

// The program's tests: the whole program, headless (no window of the system, no system dialog), on PDFs the tests
// write into their own folders. One interface at a time: -define:ODIN_TEST_THREADS=1 (feuilletool test does it).

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import config "gt:config"
import debug "gt:debug"
import host "gt:host"
import "gt:platform"
import "gt:testkit"
import session "gt:testkit/session"
import fixture "fixture"

@(private = "file")
BLUE  :: session.Color{0, 0, 255, 255}
@(private = "file")
RED   :: session.Color{255, 0, 0, 255}
@(private = "file")
WHITE :: session.Color{255, 255, 255, 255}

// The program on `path`, in a session that ends with the test.
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

// Every picture in view is there, of the layer asked and of the page's content now: the last frame laid the snapshot
// out and wanted nothing more.
pictures_ready :: proc(s: ^session.Session, app: ^App) -> bool {
	if app.snapshot == nil || app.layout.revision != app.snapshot.revision { return false }
	if app.thumbs_shown && app.thumb_layout.revision != app.snapshot.revision { return false }
	return len(app.frame_asks) == 0 && len(app.pictures) > 0
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

	// the saved copy has no protection: it opens with no password, its content kept
	copy_path := fmt.tprintf("%s/open.pdf", testkit.temp_folder(t, "feuille-copy"))
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Save, path = copy_path))
	session.wait_until(s, copy_path, proc(s: ^session.Session, p: string) -> bool { return os.exists(p) }, "the copy is written")
	app_open_file(app, copy_path, "")
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.snapshot.path != "" && app.pending == .None && app.snapshot.opened && pictures_ready(s, app) }, "the copy opens without a password")
	img = session.capture(s)
	testing.expect_value(t, page_pixel(s, app, img, 0, centre(fixture.BASE_RECT)), BLUE)
}

@(test)
what_is_not_a_pdf_is_told :: proc(t: ^testing.T) {
	dir := testkit.temp_folder(t, "feuille")
	path := fmt.tprintf("%s/notes.pdf", dir)
	junk := "not a pdf at all"
	testing.expect(t, os.write_entire_file(path, transmute([]u8)junk) == nil)
	s, app := start(t, path)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.failure != .None }, "the failure is told")
	testing.expect_value(t, app.failure, Open_Error.Format)
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
	testing.expect(t, len(app.pictures) < 10, "a few pages drawn")
	testing.expect(t, len(app.thumbs) < 40, "a few thumbnails drawn")
	session.save_png(s, "window.png")   // (build/session/: what the window showed, to look at)
}

// Another program writes the document: the new version opens; while it holds edits, the edits stay.
@(test)
a_document_written_by_another_program_opens_again :: proc(t: ^testing.T) {
	path := write_pdf(t, "watched.pdf", {})
	s, app := start(t, path)
	session.wait_until(s, app, pictures_ready, "the first version is drawn")
	testing.expect_value(t, len(app.snapshot.pages), 1)
	two := []fixture.Page{{size = {200, 200}}, {size = {200, 200}}}
	testing.expect(t, os.write_entire_file(path, fixture.make_pdf({pages = two}, context.temp_allocator)) == nil)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.snapshot != nil && len(app.snapshot.pages) == 2 }, "the second version opens")
	session.wait_text(s, "watched.pdf changed on the disk and is opened again")

	// edited: the third version is told, the edits stay
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Blank, id = app.snapshot.pages[0].id))
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.snapshot.edited }, "the document is edited")
	three := []fixture.Page{{size = {200, 200}}, {size = {200, 200}}, {size = {200, 200}}, {size = {200, 200}}, {size = {200, 200}}}
	testing.expect(t, os.write_entire_file(path, fixture.make_pdf({pages = three}, context.temp_allocator)) == nil)
	session.wait_text(s, "watched.pdf changed on the disk: your edits stay on the version opened before")
	testing.expect(t, app.snapshot.edited, "the edits stay")
	testing.expect_value(t, len(app.snapshot.pages), 3)
}

// The debug panel names the document and acts on the program: a tool shows the layer, then drops the pictures, which
// come back.
@(test)
the_debug_panel_reads_and_acts :: proc(t: ^testing.T) {
	path := write_pdf(t, "debug.pdf", {layer = true})
	s, app := start(t, path)
	session.wait_until(s, app, pictures_ready, "the page is drawn")
	sb := strings.builder_make(context.temp_allocator)
	debug.list(&app.main.state, &sb)
	testing.expect(t, strings.contains(strings.to_string(sb), "debug.pdf"), "the panel names the document")
	testing.expect_value(t, debug.set(&app.main.state, "Feuille/View/form layer", "true"), "")
	testing.expect(t, app.layer, "the tool shows the layer")
	testing.expect_value(t, debug.press(&app.main.state, "Feuille/Caches/Drop the pictures"), "")
	session.wait_until(s, app, pictures_ready, "the pictures come back")
}

// The keys go from page to page: Page Down and the right arrow to the next, Page Up and the left arrow back.
@(test)
the_keys_turn_the_pages :: proc(t: ^testing.T) {
	pages := make([]fixture.Page, 4, context.temp_allocator)
	for &p in pages { p = {size = {200, 280}} }
	s, app := start(t, write_pdf(t, "keys.pdf", {pages = pages}))
	session.wait_until(s, app, pictures_ready, "the first page is drawn")
	// (a click on the page first: the column it is in has the keyboard, as when a person reads)
	session.click(s, fmt.tprintf("page%d", app.snapshot.pages[0].id))
	Want :: struct { app: ^App, page: int }
	at :: proc(s: ^session.Session, w: Want) -> bool { return w.app.current == w.page }
	session.key(s, .Page_Down)
	session.wait_until(s, Want{app, 1}, at, "Page Down: the second page")
	session.key(s, .Right)
	session.wait_until(s, Want{app, 2}, at, "the right arrow: the third page")
	session.key(s, .Page_Up)
	session.wait_until(s, Want{app, 1}, at, "Page Up: the second page again")
	session.key(s, .Left)
	session.wait_until(s, Want{app, 0}, at, "the left arrow: the first page")
	// presses during the scroll add up: two at once go two pages on
	session.key(s, .Page_Down)
	session.key(s, .Page_Down)
	session.wait_until(s, Want{app, 2}, at, "two quick presses: the third page")
}

// Shift+F1 opens the About modal; its "What's new" button closes it and opens the built-in What's new page.
@(test)
about_modal_opens_and_jumps_to_whats_new :: proc(t: ^testing.T) {
	s, app := start(t, "")
	session.wait_text(s, "Open a PDF")
	session.key(s, .F1, {.Shift})
	session.wait_until(s, proc(s: ^session.Session) -> bool {
		b := session.find(s, "modal_about")
		return b != nil && b.transparency < 0.01 && session.find(s, "about_whats_new") != nil
	}, "the About modal is shown")
	testing.expect(t, app.about_open, "the About modal is open")
	session.click(s, "about_whats_new")
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return !app.about_open && app.settings_open }, "What's new opens in settings")
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

@(test)
compact_rows_toggles_with_ctrl_shift_alt_r :: proc(t: ^testing.T) {
	s, app := start(t, "")
	session.frames(s, 2)
	testing.expect(t, config.float_of(&app.prefs, "appearance.density") >= 1, "starts at default density")
	session.key(s, .R, {.Ctrl, .Shift, .Alt})
	testing.expect(t, config.float_of(&app.prefs, "appearance.density") < 1, "Ctrl+Shift+Alt+R enables compact rows")
	session.key(s, .R, {.Ctrl, .Shift, .Alt})
	testing.expect(t, config.float_of(&app.prefs, "appearance.density") >= 1, "Ctrl+Shift+Alt+R restores default density")
}
