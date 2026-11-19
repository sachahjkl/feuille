package feuille

// The signature, end to end: typed in a script font and placed with its date and place (one stamp, the font embedded
// in the saved copy, one undo); drawn on the pad and placed (the ink as one Outline, the mention and the caption as
// stamps around it); the strokes kept and read back.

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import ink "gt:ink"
import pdf "gt:pdf"
import "gt:testkit"
import session "gt:testkit/session"
import "gt:ui"

@(private = "file")
Sign_Wait :: struct { app: ^App, after: u64 }

@(private = "file")
next_snapshot :: proc(s: ^session.Session, app: ^App, before: u64, what: string, loc := #caller_location) {
	session.wait_until(s, Sign_Wait{app, before}, proc(s: ^session.Session, r: Sign_Wait) -> bool {
		return r.app.snapshot != nil && r.app.snapshot.revision > r.after && pictures_ready(s, r.app)
	}, what, loc = loc)
}

// The point at shares `x`, `y` of page `index`, in the window's pixels.
@(private = "file")
on_page :: proc(s: ^session.Session, app: ^App, index: int, x, y: f32) -> [2]f32 {
	b := session.get(s, fmt.tprintf("page%d", app.snapshot.pages[index].id))
	k := app.main.state.scale
	return {(b.rect.min.x + x * (b.rect.max.x - b.rect.min.x)) * k, (b.rect.min.y + y * (b.rect.max.y - b.rect.min.y)) * k}
}

@(private = "file")
dialog_ready :: proc(s: ^session.Session, app: ^App) -> bool {
	return app.sign.faces_ok && ui.view_is_open(&app.views, SIGN_VIEW) && session.find(s, "sign_place") != nil
}

@(private = "file")
preview_ready :: proc(s: ^session.Session, app: ^App) -> bool { return sign_ready_marks(app) != nil && app.sign.tex_size != {} }

@(test)
a_typed_signature_is_placed_dated_and_saved_with_its_font :: proc(t: ^testing.T) {
	s, app := start(t, write_pdf(t, "contract.pdf", {pages = {{size = {300, 400}}, {size = {300, 400}}}}))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	session.key(s, .S)
	testing.expect(t, app.tool == .Signature, "S turns the signature tool on")
	session.wait_until(s, app, dialog_ready, "the dialog opens, the fonts given to the engine")
	app.sign.sig.mode, app.sign.tab = .Typed, 0
	session.type_text(s, "Camille Dupré")
	testing.expect_value(t, app.sign.sig.name, "Camille Dupré")
	app.sign.sig.dated = true
	delete(app.sign.sig.place, runtime.heap_allocator())
	app.sign.sig.place = strings.clone("Paris", runtime.heap_allocator())   // (the App's allocator: it frees it)
	sign_changed(app)
	session.wait_until(s, app, preview_ready, "the preview of the typed name")
	session.click(s, "sign_place")
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return !ui.view_is_open(&app.views, SIGN_VIEW) }, "Place closes the dialog")
	testing.expect(t, app.tool == .Signature, "the tool stays on to place it")

	rev := app.snapshot.revision
	session.click_at(s, on_page(s, app, 0, 0.5, 0.6))
	next_snapshot(s, app, rev, "the signature placed")
	stamps := app.snapshot.pages[0].stamps
	testing.expect_value(t, len(stamps), 1)
	st := stamps[0]
	testing.expect(t, st.stamp.face != 0 && st.stamp.flourish, "in a script font, with its flourish")
	testing.expect_value(t, st.stamp.text, "Camille Dupré")
	testing.expect(t, strings.contains(st.stamp.caption, "Paris"), "its caption holds the place")
	mid := [2]f32{(st.box[0] + st.box[2]) / 2, (st.box[1] + st.box[3]) / 2}
	testing.expectf(t, abs(mid.x - 0.5) < 0.03 && abs(mid.y - 0.6) < 0.03, "centred on the click (%v)", st.box)

	// on the second page too: the tool stays on
	session.key(s, .Page_Down)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.current == 1 && pictures_ready(s, app) }, "the second page in view")
	rev = app.snapshot.revision
	session.click_at(s, on_page(s, app, 1, 0.5, 0.5))
	next_snapshot(s, app, rev, "signed on the second page")
	testing.expect_value(t, len(app.snapshot.pages[1].stamps), 1)

	path := fmt.tprintf("%s/signed.pdf", testkit.temp_folder(t, "feuille-sign"))
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Save, path = path))
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.snapshot != nil && !app.snapshot.edited }, "saved")
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	testing.expect(t, err == nil && strings.contains(string(data), "+MrsSaintDelafield") && strings.contains(string(data), "/FontFile2"), "the copy embeds the font")
	testing.expect_value(t, strings.count(string(data), "/FontFile2"), 1)

	rev = app.snapshot.revision
	session.key(s, .Z, {.Ctrl})
	next_snapshot(s, app, rev, "the last signature undone")
	testing.expect_value(t, len(app.snapshot.pages[1].stamps), 0)
	session.key(s, .Escape)
	testing.expect(t, app.tool == .None, "Escape leaves the tool")
}

@(test)
a_drawn_signature_is_ink_between_its_mention_and_its_caption :: proc(t: ^testing.T) {
	s, app := start(t, write_pdf(t, "form.pdf", {pages = {{size = {300, 400}}}}))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	session.key(s, .S)
	session.wait_until(s, app, dialog_ready, "the dialog opens")
	app.sign.sig.mode, app.sign.tab = .Drawn, 1
	app.sign.sig.mention, app.sign.sig.dated = true, true
	sign_changed(app)
	session.frames(s, 2)
	pad := session.get(s, "sign_pad")
	k := app.main.state.scale
	w, h := pad.rect.max.x - pad.rect.min.x, pad.rect.max.y - pad.rect.min.y
	at :: proc(pad: ^ui.Box, w, h, k, x, y: f32) -> [2]f32 { return {(pad.rect.min.x + x * w) * k, (pad.rect.min.y + y * h) * k} }
	session.drag(s, at(pad, w, h, k, 0.15, 0.6), at(pad, w, h, k, 0.5, 0.3))
	session.drag(s, at(pad, w, h, k, 0.3, 0.7), at(pad, w, h, k, 0.8, 0.5))
	testing.expect_value(t, len(app.sign.sig.strokes), 2)
	testing.expect_value(t, len(app.sign.pad), 2)
	testing.expect(t, len(app.sign.pad[0].points) > 2, "the pad draws the stroke's ink")
	session.wait_until(s, app, preview_ready, "the preview of the drawing")
	session.click(s, "sign_place")
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return !ui.view_is_open(&app.views, SIGN_VIEW) }, "the dialog closes")

	rev := app.snapshot.revision
	session.click_at(s, on_page(s, app, 0, 0.5, 0.5))
	next_snapshot(s, app, rev, "the drawing placed")
	p := app.snapshot.pages[0]
	testing.expect_value(t, len(p.shapes), 1)
	testing.expect_value(t, len(p.stamps), 2)
	ink_box := p.shapes[0].box
	testing.expect_value(t, p.shapes[0].shape.kind, pdf.Shape_Kind.Outline)
	gaps := 0
	for q in p.shapes[0].shape.points { if math.is_nan(q.x) { gaps += 1 } }
	testing.expect_value(t, gaps, 1)
	testing.expectf(t, !math.is_nan(ink_box[0]) && ink_box[2] > ink_box[0] && ink_box[3] > ink_box[1], "the ink has a box (%v)", ink_box)
	testing.expectf(t, p.stamps[0].box[3] <= ink_box[1] + 0.01, "the mention above the ink (%v, %v)", p.stamps[0].box, ink_box)
	testing.expectf(t, p.stamps[1].box[1] >= ink_box[3] - 0.01, "the caption under it (%v, %v)", p.stamps[1].box, ink_box)

	// the drawing is drawn on the page: dark pixels inside the ink's box
	img := session.capture(s)
	b := session.get(s, fmt.tprintf("page%d", p.id))
	dark := 0
	for y in int(b.rect.min.y + ink_box[1] * (b.rect.max.y - b.rect.min.y)) ..< int(b.rect.min.y + ink_box[3] * (b.rect.max.y - b.rect.min.y)) {
		for x in int(b.rect.min.x + ink_box[0] * (b.rect.max.x - b.rect.min.x)) ..< int(b.rect.min.x + ink_box[2] * (b.rect.max.x - b.rect.min.x)) {
			c := session.pixel(img, int(f32(x) * k), int(f32(y) * k))
			if c[0] < 160 { dark += 1 }
		}
	}
	testing.expectf(t, dark > 10, "the ink is drawn on the page (%d dark pixels)", dark)
}

@(test)
the_strokes_are_kept_as_text_and_read_back :: proc(t: ^testing.T) {
	strokes := make([dynamic]Stroke, context.temp_allocator)
	a := make(Stroke, context.temp_allocator)
	append(&a, ink.Sample{at = {10.5, 20}, time = 0}, ink.Sample{at = {30.25, 41}, time = 16})
	b := make(Stroke, context.temp_allocator)
	append(&b, ink.Sample{at = {100, 100}, time = 0})
	append(&strokes, a, b)
	text := strokes_format(strokes[:])
	back := make([dynamic]Stroke, context.temp_allocator)
	strokes_parse(text, &back)
	defer for st in back { delete(st) }
	testing.expect_value(t, len(back), 2)
	testing.expect_value(t, len(back[0]), 2)
	testing.expect_value(t, back[0][1].at, [2]f32{30.3, 41})
	testing.expect_value(t, back[0][1].time, 16)
	testing.expect_value(t, back[1][0].at, [2]f32{100, 100})
	// what does not read is skipped, and an empty text is no stroke
	junk := make([dynamic]Stroke, context.temp_allocator)
	strokes_parse("1,2;x,y,z|", &junk)
	defer for st in junk { delete(st) }
	testing.expect_value(t, len(junk), 0)
}
