package feuille

// The pictures of the README and the site: the program's own frames, headless, on the tests' sample form. Opt-in:
// `feuilletool shots` builds the tests with -define:FEUILLE_SHOTS=<folder> and runs this one alone; a plain test run
// returns at once.

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import host "gt:host"
import "gt:testkit"
import session "gt:testkit/session"
import fixture "fixture"

SHOTS :: #config(FEUILLE_SHOTS, "")

@(private = "file")
SHOT_SIZE :: [2]int{1100, 820}

@(private = "file")
shot_start :: proc(t: ^testing.T, path: string, prefs: []string = nil) -> (s: ^session.Session, app: ^App) {
	context.allocator = runtime.heap_allocator()
	app = app_open({path = path, headless = true, size = SHOT_SIZE, pref_args = prefs})
	testing.cleanup(t, proc(p: rawptr) { app_close((^App)(p)) }, app)
	s = session.attach(t, {win = app.main.win, state = &app.main.state, renderer = &app.shared.r, user = app, allocator = context.allocator,
		frame = proc(user: rawptr) { host.host_frame(&(^App)(user).main) }}, #location())
	return
}

@(private = "file")
drawn :: proc(s: ^session.Session, app: ^App) -> bool {
	if app.snapshot == nil || len(app.last_ask) == 0 { return false }
	for a in app.last_ask {
		shown, ok := app.pictures[a.id]
		if !ok || shown.size != a.size || shown.layer != a.layer { return false }
	}
	return true
}

@(private = "file")
save :: proc(s: ^session.Session, name: string) {
	session.frames(s, 4)   // (what the last change set off settles: the halos, the fades)
	session.save_png(s, name)
	from := session.out_path(s, name)
	data, err := os.read_entire_file_from_path(from, context.temp_allocator)
	if err == nil { _ = os.write_entire_file(fmt.tprintf("%s/%s", SHOTS, name), data) }
}

@(test)
shots :: proc(t: ^testing.T) {
	when SHOTS == "" { return }
	dir := testkit.temp_folder(t, "feuille-shots")
	sample := fmt.tprintf("%s/application-form.pdf", dir)
	testing.expect(t, os.write_entire_file(sample, fixture.make_sample(context.temp_allocator)) == nil)
	locked := fmt.tprintf("%s/protected.pdf", dir)
	testing.expect(t, os.write_entire_file(locked, fixture.make_pdf({layer = true, password = "secret"}, context.temp_allocator)) == nil)

	{
		s, app := shot_start(t, sample)
		session.wait_until(s, app, drawn, "the form is drawn")
		save(s, "main.png")
		session.key(s, .L, {.Ctrl})
		session.wait_until(s, app, drawn, "the form is drawn with its layer")
		save(s, "layer.png")
		session.key(s, .L, {.Ctrl})
		session.wait_until(s, app, drawn, "the form is drawn masked again")
		session.key(s, .K, {.Ctrl})
		save(s, "palette.png")
		session.key(s, .Escape)
		session.key(s, .Comma, {.Ctrl})
		session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.settings_open }, "the settings open")
		save(s, "settings.png")
	}
	{
		s, app := shot_start(t, sample, {"--pref", "appearance.mode=light"})
		session.wait_until(s, app, drawn, "the form is drawn, light")
		save(s, "light.png")
	}
	{
		s, app := shot_start(t, locked)
		session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.pending == .Locked }, "the password is asked")
		save(s, "locked.png")
	}
	{
		s, _ := shot_start(t, "")
		session.wait_text(s, "Open a PDF")
		save(s, "empty.png")
	}
}
