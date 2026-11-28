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
import "gt:turn"
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
	testing.expect(t, len(app.sign.pad[0].points) > 2, "the pad draws the stroke under way at once")
	session.wait_until(s, app, preview_ready, "the preview of the drawing")
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool {
		return app.sign.pad_tex_px != {} && app.sign.pad_shown == 2 && app.sign.pad_tex_epoch == app.sign.pad_epoch
	}, "the pad shows the engine's ink of both strokes")
	session.click(s, "sign_place")
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return !ui.view_is_open(&app.views, SIGN_VIEW) }, "the dialog closes")

	rev := app.snapshot.revision
	session.click_at(s, on_page(s, app, 0, 0.5, 0.5))
	next_snapshot(s, app, rev, "the drawing placed")
	p := app.snapshot.pages[0]
	// (each stroke's ink in levels: at least one Outline a stroke, every part of the signature in one group)
	testing.expect(t, len(p.shapes) >= 2, "the two strokes' ink")
	testing.expect_value(t, len(p.stamps), 2)
	g := p.stamps[0].stamp.group
	testing.expect(t, g != 0, "the signature is a group")
	ink_box := [4]f32{max(f32), max(f32), min(f32), min(f32)}
	for sh in p.shapes {
		testing.expect_value(t, sh.shape.kind, pdf.Shape_Kind.Outline)
		testing.expect_value(t, sh.shape.group, g)
		ink_box = {min(ink_box[0], sh.box[0]), min(ink_box[1], sh.box[1]), max(ink_box[2], sh.box[2]), max(ink_box[3], sh.box[3])}
	}
	testing.expect_value(t, p.stamps[1].stamp.group, g)
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

	// a drag on its ink moves the whole signature; Delete takes all of it, one undo brings it back
	before := group_box(p, g)
	from := on_page(s, app, 0, (p.stamps[0].box[0] + p.stamps[0].box[2]) / 2, (p.stamps[0].box[1] + p.stamps[0].box[3]) / 2)
	rev = app.snapshot.revision
	session.drag(s, from, from + {0, 0.1 * (b.rect.max.y - b.rect.min.y) * k})
	next_snapshot(s, app, rev, "the signature moved")
	after := group_box(app.snapshot.pages[0], g)
	testing.expectf(t, abs(after[1] - before[1] - 0.1) < 0.02 && abs(after[3] - before[3] - 0.1) < 0.02, "all of it went down (%v to %v)", before, after)
	testing.expect_value(t, app.chosen.group, g)
	rev = app.snapshot.revision
	session.key(s, .Delete)
	next_snapshot(s, app, rev, "the signature removed")
	testing.expect_value(t, len(app.snapshot.pages[0].stamps) + len(app.snapshot.pages[0].shapes), 0)
	rev = app.snapshot.revision
	session.key(s, .Z, {.Ctrl})
	next_snapshot(s, app, rev, "the removal undone")
	testing.expect_value(t, len(app.snapshot.pages[0].stamps), 2)
}

// A stylus on the pad: its pressure comes into the stroke's samples, rising as the pen presses harder.
@(test)
a_stylus_s_pressure_reaches_the_stroke :: proc(t: ^testing.T) {
	s, app := start(t, write_pdf(t, "pen.pdf", {pages = {{size = {300, 400}}}}))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	session.key(s, .S)
	session.wait_until(s, app, dialog_ready, "the dialog opens")
	app.sign.sig.mode, app.sign.tab = .Drawn, 1
	sign_changed(app)
	session.frames(s, 2)
	pad := session.get(s, "sign_pad")
	k := app.main.state.scale
	w, h := pad.rect.max.x - pad.rect.min.x, pad.rect.max.y - pad.rect.min.y
	from := [2]f32{(pad.rect.min.x + 0.2 * w) * k, (pad.rect.min.y + 0.5 * h) * k}
	to := [2]f32{(pad.rect.min.x + 0.8 * w) * k, (pad.rect.min.y + 0.4 * h) * k}
	session.pen_drag(s, from, to, {0.2, 0.9})
	testing.expect_value(t, len(app.sign.sig.strokes), 1)
	if len(app.sign.sig.strokes) == 1 {
		st := app.sign.sig.strokes[0]
		testing.expect(t, len(st) > 2, "the pen's moves are samples")
		first, last := st[0].pressure, st[len(st) - 1].pressure
		testing.expectf(t, first > 0 && last > first, "the pressure is the pen's, rising (%v to %v)", first, last)
	}
}

// The words are the signature's language's, whatever the program's: its mention, its caption's turn, its date.
@(test)
a_signature_s_words_are_in_its_own_language :: proc(t: ^testing.T) {
	testing.expect_value(t, sign_date(.French, {2026, 11, 21}, context.temp_allocator), "21/11/2026")
	testing.expect_value(t, sign_date(.English, {2026, 11, 21}, context.temp_allocator), "21 November 2026")
	testing.expect_value(t, sign_date(.German, {2026, 3, 5}, context.temp_allocator), "05.03.2026")
	testing.expect_value(t, sign_date(.Dutch, {2026, 3, 5}, context.temp_allocator), "05-03-2026")
	testing.expect_value(t, days_in_month(2, 2024), 29)
	testing.expect_value(t, days_in_month(2, 2026), 28)
	s := SIGNATURE_DEFAULT
	s.dated, s.place, s.date = true, "Lyon", {2026, 11, 21}
	cases := [?]struct { lang: Sign_Lang, want: string }{
		{.French, "Fait à Lyon, le 21/11/2026"},
		{.English, "Done at Lyon, on 21 November 2026"},
		{.German, "Lyon, den 21.11.2026"},
		{.Spanish, "En Lyon, a 21/11/2026"},
		{.Italian, "Lyon, lì 21/11/2026"},
		{.Dutch, "Opgemaakt te Lyon op 21-11-2026"},
	}
	for c in cases {
		s.lang = c.lang
		testing.expect_value(t, signature_caption(s), c.want)
	}
	s.lang, s.place = .French, ""
	testing.expect_value(t, signature_caption(s), "Le 21/11/2026")
	s.place, s.date = "Lyon", {}
	testing.expect_value(t, signature_caption(s), "Fait à Lyon")
	// (kept and read back with its language)
	s.lang = .German
	text := signatures_text({s}, context.temp_allocator)
	back, ok := signatures_parse(text)
	defer {
		for &b in back { signature_free(&b) }
		delete(back)
	}
	testing.expect(t, ok && len(back) == 1 && back[0].lang == .German, "the language is kept")
}

// The date field opens its drums, steps its parts, and Escape closes the drums before the dialog.
// The preview zooms: the wheel over it enlarges the signature, and a finer picture comes for it, the same size on the
// paper (its points at the interface's scale).
@(test)
the_preview_zooms_into_a_finer_picture :: proc(t: ^testing.T) {
	s, app := start(t, write_pdf(t, "zoom.pdf", {}))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	session.key(s, .S)
	session.wait_until(s, app, dialog_ready, "the dialog opens")
	app.sign.sig.mode, app.sign.tab = .Typed, 0
	session.type_text(s, "Camille")
	// (the picture for the zoom that fits it: the one the dialog keeps until a zoom asks more)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool {
		return preview_ready(s, app) && app.sign.preview.px_per_pt == app.sign.detail
	}, "the preview")
	first := app.sign.preview.px_per_pt
	b := session.get(s, "sign_preview")
	k := app.main.state.scale
	session.wheel(s, (b.rect.min + b.rect.max) / 2 * k, {0, -8})
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.sign.zoom.zoom > 1 }, "the wheel zooms")
	session.wait_until(s, Sign_Wait{app, u64(first * 1000)}, proc(s: ^session.Session, r: Sign_Wait) -> bool {
		p := r.app.sign.preview
		return p != nil && u64(p.px_per_pt * 1000) > r.after && r.app.sign.tex_size == p.px
	}, "a finer picture for the zoom")
	testing.expect(t, sign_detail(1, 1) == 2 && sign_detail(1, 3) == 8 && sign_detail(1, 100) == SIGN_DETAIL_MOST, "the steps of the detail")
}

@(test)
the_date_picker_opens_its_drums_and_steps_a_part :: proc(t: ^testing.T) {
	s, app := start(t, write_pdf(t, "date.pdf", {pages = {{size = {300, 400}}}}))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	session.key(s, .S)
	session.wait_until(s, app, dialog_ready, "the dialog opens")
	app.sign.sig.dated = true
	app.sign.sig.date = {2026, 3, 10}
	sign_changed(app)
	session.frames(s, 3)
	// (the click lands on the middle part, the month; Up steps it, Left then Up steps the day)
	session.click(s, "sign_when")
	testing.expect(t, session.find(s, "drums") != nil, "clicking the date opens its drums")
	session.key(s, .Up)
	testing.expect_value(t, app.sign.sig.date.month, 4)
	session.key(s, .Left)
	session.key(s, .Up)
	testing.expect_value(t, app.sign.sig.date.day, 11)
	session.key(s, .Escape)
	testing.expect(t, session.find(s, "drums") == nil && ui.view_is_open(&app.views, SIGN_VIEW), "Escape closes the drums, not the dialog")
}

// The exported file's text read back gives the same signatures; another file is refused.
@(test)
the_signatures_file_reads_back_what_it_wrote :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator()
	typed := SIGNATURE_DEFAULT
	typed.name, typed.script, typed.tilt, typed.dated, typed.place = "Camille Dupré", .Sacramento, -3, true, "Lyon"
	drawn := SIGNATURE_DEFAULT
	drawn.mode, drawn.pen, drawn.ink = .Drawn, .Brush, {20, 20, 24}
	st := make(Stroke, context.temp_allocator)
	append(&st, ink.Sample{at = {10, 20}}, ink.Sample{at = {40, 25}, time = 12})
	drawn.strokes = make([dynamic]Stroke, context.temp_allocator)
	append(&drawn.strokes, st)
	text := signatures_text({typed, drawn}, context.temp_allocator)
	testing.expect(t, strings.has_prefix(text, SIGNATURES_HEADER + "\n"), "its first line says what it is")
	back, ok := signatures_parse(text)
	defer {
		for &b in back { signature_free(&b) }
		delete(back)
	}
	testing.expect(t, ok, "it reads")
	testing.expect_value(t, len(back), 2)
	if len(back) == 2 {
		testing.expect_value(t, signature_key(back[0]), signature_key(typed))
		testing.expect_value(t, signature_key(back[1]), signature_key(drawn))
		testing.expect_value(t, back[0].name, "Camille Dupré")
		testing.expect_value(t, len(back[1].strokes), 1)
	}
	_, other := signatures_parse("name\tCamille\n")
	testing.expect(t, !other, "a file without the header is not one")
}

// The library in the window: a new signature, chosen; the first chosen again, as it was; exported, removed, imported
// back (once: a second import adds nothing).
@(test)
signatures_are_added_chosen_exported_and_imported :: proc(t: ^testing.T) {
	s, app := start(t, write_pdf(t, "lib.pdf", {pages = {{size = {300, 400}}}}))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	session.key(s, .S)
	session.wait_until(s, app, dialog_ready, "the dialog opens")
	app.sign.sig.mode, app.sign.tab = .Typed, 0
	session.type_text(s, "Camille")
	testing.expect_value(t, len(app.sign.lib), 1)

	session.click(s, "sign_new")
	testing.expect_value(t, len(app.sign.lib), 2)
	testing.expect_value(t, app.sign.chosen, 1)
	testing.expect_value(t, app.sign.sig.name, "")
	session.type_text(s, "C.D.")
	session.click(s, "sign_card0")
	testing.expect_value(t, app.sign.chosen, 0)
	testing.expect_value(t, app.sign.sig.name, "Camille")
	testing.expect_value(t, ui.line_edit_string(&app.sign.name), "Camille")
	testing.expect_value(t, app.sign.lib[1].name, "C.D.")

	path := fmt.tprintf("%s/mine.%s", testkit.temp_folder(t, "feuille-signatures"), SIGNATURES_EXT)
	sign_file_start(app, path, false)
	session.wait_until(s, path, proc(s: ^session.Session, path: string) -> bool { return os.exists(path) }, "the signatures are exported")
	session.frames(s, 2)

	session.click(s, "sign_card1")
	session.click(s, "sign_remove")
	testing.expect_value(t, len(app.sign.lib), 1)
	sign_file_start(app, path, true)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return len(app.sign.lib) == 2 }, "the removed one comes back")
	testing.expect_value(t, app.sign.lib[1].name, "C.D.")
	testing.expect_value(t, app.sign.chosen, 1)
	sign_file_start(app, path, true)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return strings.contains(app.status, "already") }, "a second import adds nothing")
	testing.expect_value(t, len(app.sign.lib), 2)
}

@(test)
the_strokes_are_kept_as_text_and_read_back :: proc(t: ^testing.T) {
	strokes := make([dynamic]Stroke, context.temp_allocator)
	a := make(Stroke, context.temp_allocator)
	append(&a, ink.Sample{at = {10.5, 20}, time = 0}, ink.Sample{at = {30.25, 41}, time = 16})
	b := make(Stroke, context.temp_allocator)
	append(&b, ink.Sample{at = {100, 100}, time = 0})
	c := make(Stroke, context.temp_allocator)
	append(&c, ink.Sample{at = {5, 6}, time = 0, pressure = 0.5}, ink.Sample{at = {7, 8}, time = 9, pressure = 0.25, tilt = {turn.from_degrees(f32(30)), turn.from_degrees(f32(-12.5))}})
	append(&strokes, a, b, c)
	text := strokes_format(strokes[:])
	// (the file keeps the tilt in tenths of a degree: files written before the tilt was in turns still read)
	testing.expect(t, strings.has_suffix(text, ",250,300,-125"), text)
	back := make([dynamic]Stroke, context.temp_allocator)
	strokes_parse(text, &back)
	defer for st in back { delete(st) }
	testing.expect_value(t, len(back), 3)
	testing.expect_value(t, len(back[0]), 2)
	if len(back) == 3 {
		testing.expect_value(t, back[2][0].pressure, 0.5)
		testing.expect_value(t, back[2][0].tilt, [2]f32{})
		testing.expect_value(t, back[2][1].pressure, 0.25)
		testing.expect_value(t, back[2][1].tilt, [2]f32{turn.from_degrees(f32(30)), turn.from_degrees(f32(-12.5))})
	}
	testing.expect_value(t, back[0][1].at, [2]f32{30.3, 41})
	testing.expect_value(t, back[0][1].time, 16)
	testing.expect_value(t, back[1][0].at, [2]f32{100, 100})
	// what does not read is skipped, and an empty text is no stroke
	junk := make([dynamic]Stroke, context.temp_allocator)
	strokes_parse("1,2;x,y,z|", &junk)
	defer for st in junk { delete(st) }
	testing.expect_value(t, len(junk), 0)
}

// The signature dialog switches between "Type it" and "Draw it" with Segmented tabs directly on the dialog's surface,
// with no separate page frame around the chosen tab's content.
@(test)
the_signature_tabs_use_segmented_style_without_a_page_frame :: proc(t: ^testing.T) {
	s, app := start(t, write_pdf(t, "tabs.pdf", {pages = {{size = {300, 400}}}}))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	session.key(s, .S)
	session.wait_until(s, app, dialog_ready, "the dialog opens")
	session.frames(s, 30)   // (the dialog's fade settles)
	testing.expect(t, session.find(s, "sign_tab_page") == nil, "no manual page frame under the tabs")
	testing.expect(t, session.find(s, "sign_tab_row") == nil, "no manual tab_line_draw row")
	t0 := session.get(s, "sign_tabs_0")
	t1 := session.get(s, "sign_tabs_1")
	testing.expect(t, app.sign.sig.mode == .Typed && app.sign.tab == 0, "starts on Type it")
	testing.expect(t, session.find(s, "sign_name") != nil && session.find(s, "sign_pad") == nil, "shows typed controls")

	// The chosen key and the unchosen track stand apart from each other and from the dialog's surface.
	k := app.main.state.scale
	session.move(s, {5, 5})
	session.frames(s, 4)
	img := session.capture(s)
	y := int(session.center(t0).y * k)
	key := session.pixel(img, int((t0.rect.min.x + 4) * k), y)
	track := session.pixel(img, int((t1.rect.min.x + 4) * k), y)
	ground := session.pixel(img, int((t1.rect.max.x + 24) * k), y)
	testing.expectf(t, !session.near(track, ground, 4), "the track stands off the dialog surface: %v vs %v", track, ground)
	testing.expectf(t, !session.near(key, track, 4) && !session.near(key, ground, 4), "the chosen key stands off its track: %v vs %v", key, track)

	session.click(s, "sign_tabs_1")
	session.frames(s, 2)
	testing.expect_value(t, app.sign.tab, 1)
	testing.expect_value(t, app.sign.sig.mode, Sign_Mode.Drawn)
	testing.expect(t, session.find(s, "sign_pad") != nil && session.find(s, "sign_name") == nil, "shows drawn controls")

	session.click(s, "sign_tabs_0")
	session.frames(s, 2)
	testing.expect_value(t, app.sign.tab, 0)
	testing.expect_value(t, app.sign.sig.mode, Sign_Mode.Typed)
	testing.expect(t, session.find(s, "sign_name") != nil && session.find(s, "sign_pad") == nil, "shows typed controls again")
}
