package feuille

// The pictures of the README and the site: the program's own frames, headless, on the tests' sample form. Opt-in:
// `feuilletool shots` builds the tests with -define:FEUILLE_SHOTS=<folder> and runs this one alone; a plain test run
// returns at once.

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import host "gt:host"
import ink "gt:ink"
import "gt:testkit"
import session "gt:testkit/session"
import "gt:ui"
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
drawn :: proc(s: ^session.Session, app: ^App) -> bool { return pictures_ready(s, app) }

@(private = "file")
Shot_Revision :: struct { app: ^App, after: u64 }

@(private = "file")
save :: proc(s: ^session.Session, name: string) {
	session.frames(s, 4)   // (what the last change set off settles: the halos, the fades)
	session.save_png(s, name)
	from := session.out_path(s, name)
	data, err := os.read_entire_file_from_path(from, context.temp_allocator)
	if err == nil { _ = os.write_entire_file(fmt.tprintf("%s/%s", SHOTS, name), data) }
}

// A hand's signature on the pad: a capital's loop, a run of small arches, a long stroke back under them; each sampled
// at a pointer's rate, faster on the straight runs than in the turns.
@(private = "file")
shot_signature_strokes :: proc(app: ^App) {
	context.allocator = runtime.heap_allocator()
	s := &app.sign.sig
	for st in s.strokes { delete(st) }
	clear(&s.strokes)
	stroke :: proc(s: ^Signature, n: int, at: proc(u: f32) -> [2]f32) {
		st := make(Stroke)
		t: f64 = 0
		last := at(0)
		for i in 0 ..= n {
			p := at(f32(i) / f32(n))
			d := p - last
			// (the hand slows where the line turns: time follows the curvature less than the length)
			t += f64(math.sqrt(d.x * d.x + d.y * d.y)) / 0.9 + 4
			append(&st, ink.Sample{at = p, time = t})
			last = p
		}
		append(&s.strokes, st)
	}
	// (a capital's open curl, from its top right round to its foot)
	stroke(s, 80, proc(u: f32) -> [2]f32 {
		a := -0.5 + u * 1.75 * math.PI
		return {125 + 48 * math.cos(a + math.PI / 2) * (1 + 0.25 * u), 92 - 62 * math.sin(a + math.PI / 2) * (1 - 0.15 * u)}
	})
	// (the small letters: a prolate cycloid's loops, rising a little to the right)
	stroke(s, 220, proc(u: f32) -> [2]f32 {
		t := u * 9 * math.PI
		return {150 + 10 * t - 15 * math.sin(t), 128 - 14 - 16 * math.cos(t) - u * 14}
	})
	// (the flourish back under it)
	stroke(s, 70, proc(u: f32) -> [2]f32 {
		return {455 - u * 360, 150 + 12 * math.sin(u * math.PI) - u * 10}
	})
	sign_pad_redo(&app.sign)
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
		// the text tool: a name written in the form's empty field, on a yellow ground
		page := session.get(s, fmt.tprintf("page%d", app.snapshot.pages[0].id))
		k := app.main.state.scale
		w, h := page.rect.max.x - page.rect.min.x, page.rect.max.y - page.rect.min.y
		session.key(s, .T)
		app.style = {size = 16, font = {family = .Serif, bold = true}, color = {29, 78, 216}, background = {253, 230, 138, 255}}
		session.click_at(s, {(page.rect.min.x + 0.36 * w) * k, (page.rect.min.y + 0.245 * h) * k})
		session.type_text(s, "Camille Martin")
		rev := app.snapshot.revision
		session.key(s, .Return)
		session.wait_until(s, Shot_Revision{app, rev}, proc(s: ^session.Session, r: Shot_Revision) -> bool { return r.app.snapshot.revision > r.after && pictures_ready(s, r.app) }, "the text is on the page")
		// the title circled in red, a line of the statement highlighted
		at := proc(page: ^ui.Box, w, h, k, x, y: f32) -> [2]f32 { return {(page.rect.min.x + x * w) * k, (page.rect.min.y + y * h) * k} }
		session.key(s, .E)
		rev = app.snapshot.revision
		session.drag(s, at(page, w, h, k, 0.08, 0.068), at(page, w, h, k, 0.63, 0.112))
		session.wait_until(s, Shot_Revision{app, rev}, proc(s: ^session.Session, r: Shot_Revision) -> bool { return r.app.snapshot.revision > r.after && pictures_ready(s, r.app) }, "the title is circled")
		session.key(s, .H)
		rev = app.snapshot.revision
		session.drag(s, at(page, w, h, k, 0.105, 0.405), at(page, w, h, k, 0.75, 0.423))
		session.wait_until(s, Shot_Revision{app, rev}, proc(s: ^session.Session, r: Shot_Revision) -> bool { return r.app.snapshot.revision > r.after && pictures_ready(s, r.app) }, "a line is highlighted")
		save(s, "text.png")
		// the signature: typed, dated, placed on the form's signature line; then a drawn one in the dialog
		session.key(s, .Escape)
		session.key(s, .S)
		session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.sign.faces_ok && session.find(s, "sign_place") != nil }, "the signature's dialog")
		session.type_text(s, "Camille Martin")
		app.sign.sig.dated = true
		delete(app.sign.sig.place, runtime.heap_allocator())
		app.sign.sig.place = strings.clone("Lyon", runtime.heap_allocator())
		ui.line_edit_set(&app.sign.place, "Lyon")
		sign_changed(app)
		session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return sign_ready_marks(app) != nil }, "the signature's preview")
		session.frames(s, 30)   // (the dialog's fade ends)
		save(s, "signature.png")
		session.click(s, "sign_place")
		// (the form's foot in view: its signature's place)
		session.wheel(s, at(page, w, h, k, 0.5, 0.5), {0, 5})
		session.frames(s, 30)
		page = session.get(s, fmt.tprintf("page%d", app.snapshot.pages[0].id))
		rev = app.snapshot.revision
		session.click_at(s, at(page, w, h, k, 0.68, 0.9))
		session.wait_until(s, Shot_Revision{app, rev}, proc(s: ^session.Session, r: Shot_Revision) -> bool { return r.app.snapshot.revision > r.after && pictures_ready(s, r.app) }, "the form is signed")
		session.move(s, at(page, w, h, k, 0.3, 0.9))
		save(s, "signed.png")
		session.click(s, "sign_change")
		session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return session.find(s, "sign_place") != nil }, "the dialog again")
		app.sign.sig.mode, app.sign.tab = .Drawn, 1
		shot_signature_strokes(app)
		sign_changed(app)
		session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return sign_ready_marks(app) != nil }, "the drawing's preview")
		session.frames(s, 30)
		save(s, "signature-drawn.png")
		session.key(s, .Escape)
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
