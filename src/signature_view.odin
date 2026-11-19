package feuille

// The signature's dialog, its pad and its placing (src/md/features/signature.md). The interface draws the font list
// and the pad itself, so typing and drawing never wait; the preview under them is the preview thread's picture
// (signature_thread.odin), the signature as it goes on the page.

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"
import "gt:draw"
import "gt:font"
import host "gt:host"
import i18n "gt:i18n"
import ink "gt:ink"
import lucide "gt:lucide"
import pdf "gt:pdf"
import "gt:render"
import store "gt:store"
import "gt:ui"

SIGN_VIEW :: "signature"
// The dialog's answer that places the signature.
SIGN_PLACE :: 1
// The pad keeps a sample when the pointer went this far, in the pad's units.
SIGN_STEP :: 1.5

// The signature's state in the window: what the dialog edits, the engine's fonts, the newest preview.
Sign_State :: struct {
	thread:    Sign_Thread,
	store:     store.Store,
	sig:       Signature,                  // what the dialog edits (owned)
	faces:     [Script]pdf.Face,           // the engine's ids of the fonts (faces_ok: given)
	faces_ok:  bool,
	ui_fonts:  [Script]font.Font_Id,       // the interface's copies, for the list (0: not read yet)
	name:      ui.Line_Edit,
	place:     ui.Line_Edit,
	date:      ui.Line_Edit,
	version:   u64,                        // moves with each change of `sig`
	asked:     u64,                        // the version last asked of the preview thread
	preview:   ^Sign_Preview,              // the newest answer (owned; nil: none yet)
	tex:       render.Texture,
	tex_size:  [2]int,                     // {}: no texture
	tab:       int,                        // the dialog's tab (Sign_Mode)
	focus:     bool,                       // the next build gives the name's field the keyboard
	pad:       [dynamic]draw.Path,         // each stroke's ink, a filled outline in the pad's units (made when it changes)
	drawing:   bool,                       // a stroke under way
	stroke_ms: f64,                        // its start, ui clock
	hover:     Sign_Hover,
}

// Where the pointer is over a page while the tool is on: the ghost of the signature follows it.
Sign_Hover :: struct {
	id:    u64,
	at:    [2]f32,   // shares of the page shown
	frame: u64,      // the frame that saw it
}

sign_init :: proc(app: ^App) {
	s := &app.sign
	store.open(&s.store, app.headless ? "" : signature_path())
	s.sig = signature_load(&s.store)
	s.tab = int(s.sig.mode)
	ui.line_edit_set(&s.name, s.sig.name)
	ui.line_edit_set(&s.place, s.sig.place)
	ui.line_edit_set(&s.date, s.sig.date)
	s.pad = make([dynamic]draw.Path)
	sign_pad_redo(s)
	s.version = 1
	sign_thread_start(&s.thread, {state = &app.main.state, user = app, faces = on_sign_faces, preview = on_sign_preview})
	ui.view_register(&app.views, SIGN_VIEW, signature_view, {title = i18n.later("Signature"), icon = lucide.SIGNATURE, icon_font = ui.lucide_icons(), width_em = 40})
}

// Before the renderer goes: the thread ends, the texture goes, the store writes what is left.
sign_close :: proc(app: ^App) {
	s := &app.sign
	sign_thread_stop(&s.thread)
	if s.tex_size != {} { render.destroy_texture(&app.shared.r, s.tex) }
	s.tex_size = {}
	if s.preview != nil { sign_preview_free(s.preview) }
	s.preview = nil
	store.close(&s.store)
	signature_free(&s.sig)
	ui.line_edit_destroy(&s.name)
	ui.line_edit_destroy(&s.place)
	ui.line_edit_destroy(&s.date)
	for &p in s.pad { draw.path_destroy(&p) }
	delete(s.pad)
}

@(private = "file")
on_sign_faces :: proc(data: rawptr, _: u64) {
	f := (^Sign_Faces)(data)
	defer free(f)
	app := (^App)(f.user)
	app.sign.faces, app.sign.faces_ok = f.faces, f.ok
	host.host_settle(&app.main)
}

@(private = "file")
on_sign_preview :: proc(data: rawptr, _: u64) {
	p := (^Sign_Preview)(data)
	app := (^App)(p.user)
	s := &app.sign
	// (an answer older than the one shown: a newer ask overtook it)
	if s.preview != nil && p.serial < s.preview.serial {
		sign_preview_free(p)
		return
	}
	if s.preview != nil { sign_preview_free(s.preview) }
	s.preview = p
	r := &app.shared.r
	if s.tex_size != p.px && s.tex_size != {} {
		render.destroy_texture(r, s.tex)
		s.tex_size = {}
	}
	if p.rgba != nil {
		if s.tex_size == {} { s.tex = render.create_texture_rgba(r, p.px.x, p.px.y) }
		s.tex_size = p.px
		render.update_texture_rgba(r, s.tex, 0, 0, p.px.x, p.px.y, p.rgba)
	}
	host.host_settle(&app.main)
}

// The marks a click places now (nil: none: the fonts are not given yet, nothing to place, or its preview is older
// than the signature).
sign_ready_marks :: proc(app: ^App) -> ^Sign_Marks {
	s := &app.sign
	p := s.preview
	if p == nil || p.serial != s.version || p.marks.size.x <= 0 { return nil }
	return &p.marks
}

// The signature changed: a new preview is asked at the end of the build.
sign_changed :: proc(app: ^App) {
	app.sign.version += 1
}

// Each build: the newest signature to the preview thread, and the dialog's answer.
sign_follow :: proc(app: ^App) {
	s := &app.sign
	if s.faces_ok && s.asked != s.version {
		s.asked = s.version
		sign_thread_ask(&s.thread, s.version, s.sig, ui.scale() * 2)
	}
	if code, ok := ui.view_ended(&app.views, SIGN_VIEW); ok {
		if code == SIGN_PLACE {
			signature_keep(&s.store, s.sig)
			say(app, i18n.tr("Click on a page to sign there; Escape leaves"))
		} else if app.tool == .Signature {
			tool_toggle(app, .Signature)
		}
	}
}

// The dialog, with the signature kept; its fonts read into the interface at its first opening.
sign_open :: proc(app: ^App) {
	s := &app.sign
	for f, k in SCRIPTS {
		if s.ui_fonts[k] != 0 { continue }
		// (compiled in: read in place, nothing from the disk)
		if id, ok := font.load_embedded(&app.shared.fonts, f.data); ok { s.ui_fonts[k] = id }
	}
	s.focus = s.sig.mode == .Typed
	ui.view_open(&app.views, SIGN_VIEW, app)
}

// The signature placed on page `p`, centred on `at` (shares of the page shown).
sign_place :: proc(app: ^App, p: Snapshot_Page, at: [2]f32) {
	m := sign_ready_marks(app)
	if m == nil || p.size.x <= 0 || p.size.y <= 0 { return }
	w := &app.worker
	a := edit_ask_make(w, .Sign, id = p.id)
	a.at = at - m.size / 2 / p.size
	a.marks = sign_marks_clone(m^, w.allocator)
	worker_edit(w, a)
}

// The ink's colour: the next signatures', and the chosen signature mark's.
sign_ink_set :: proc(app: ^App, c: [3]u8) {
	s := &app.sign
	if s.sig.ink == c { return }
	s.sig.ink = c
	sign_changed(app)
	signature_keep(&s.store, s.sig)
	ch := app.chosen
	if ch.kind == .None || app.snapshot == nil { return }
	w := &app.worker
	for q in app.snapshot.pages {
		if q.id != ch.id { continue }
		if ch.kind == .Stamp && ch.index < len(q.stamps) {
			st := q.stamps[ch.index].stamp
			st.color = c
			worker_edit(w, stamp_ask_make(w, ch.id, ch.index, st, st.text))
		}
		if ch.kind == .Shape && ch.index < len(q.shapes) && q.shapes[ch.index].shape.kind == .Outline {
			style := q.shapes[ch.index].shape
			style.fill = {c[0], c[1], c[2], 255}
			worker_edit(w, shape_ask_make(w, ch.id, ch.index, style))
		}
	}
}

////////////////////////////////
// The dialog

@(private = "file")
signature_view :: proc(v: ^ui.View, app: ^App) {
	context.allocator = runtime.heap_allocator()   // (the signature's strings are the App's)
	s := &app.sign
	sig := &s.sig
	em := ui.font_size()
	if ui.dialog_body("body") {
		ui.next({width = ui.fill(), height = ui.children_sum()})
		if ui.row(.Center) {
			ui.spacer(ui.fill())
			if ui.segmented("###sign_tabs", {i18n.tr("Type it"), i18n.tr("Draw it")}, &s.tab) {
				sig.mode = Sign_Mode(s.tab)
				s.focus = sig.mode == .Typed
				sign_changed(app)
			}
			ui.spacer(ui.fill())
		}
		ui.space(ui.SPACE_3)
		switch sig.mode {
		case .Typed: typed_part(app, em)
		case .Drawn: drawn_part(app, em)
		}
		ui.space(ui.SPACE_3)
		common_part(app, em)
		ui.space(ui.SPACE_3)
		preview_part(app, em)
	}
	if ui.dialog_buttons("buttons") {
		if ui.button("sign_cancel", i18n.tr("Cancel")).clicked { ui.view_end(v, ui.VIEW_CANCELLED) }
		ready := signature_ready(sig^) && s.faces_ok
		if ui.button("sign_place", i18n.tr("Place on the page"), lucide.SIGNATURE, {intent = .Primary, disabled = !ready, icon_font = ui.lucide_icons()}).clicked {
			ui.view_end(v, SIGN_PLACE)
		}
	}
}

@(private = "file")
typed_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	ui.next({width = ui.fill()})
	res := ui.line_edit("###sign_name", &s.name, {placeholder = i18n.tr("Your name, as you sign it")})
	if s.focus {
		ui.set_focus(res.box.key)
		s.focus = false
	}
	if res.changed {
		delete(s.sig.name)
		s.sig.name = strings.clone(ui.line_edit_string(&s.name))
		sign_changed(app)
	}
	ui.space(ui.SPACE_2)
	// (each font shows the name in it: the person chooses the hand, not a font's name)
	shown := strings.trim_space(s.sig.name)
	gap := math.round(em * 0.4)
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X, gap = {gap, gap}})
	if ui.parent(ui.build_box({.Wrap}, "###sign_fonts")) {
		for f, k in SCRIPTS {
			word := shown != "" ? shown : f.name
			ui.next({width = ui.px(em * 11.6), height = ui.px(em * 3.4), font = s.ui_fonts[k], font_size = em * 1.6 * f.scale, text_pad = em * 0.6})
			if ui.button(fmt.tprintf("sign_script%d", int(k)), word, o = {face = s.sig.script == k ? .Toggled : .Raised, tip = f.name}).clicked && s.sig.script != k {
				s.sig.script = k
				sign_changed(app)
			}
		}
	}
	ui.space(ui.SPACE_2)
	if ui.form_row(i18n.tr("Slant")) {
		if ui.slider("###sign_tilt", &s.sig.tilt, -10, 15, 1, "%.0f°", 4) { sign_changed(app) }
	}
	if ui.form_row(i18n.tr("Pen weight")) {
		if ui.slider("###sign_weight", &s.sig.weight, 0, 60, 5, "%.0f", 20) { sign_changed(app) }
	}
	ui.next({width = ui.fill()})
	if ui.toggle("###sign_flourish", i18n.tr("A flourish under the name"), &s.sig.flourish) { sign_changed(app) }
}

@(private = "file")
drawn_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	pad_build(app, em)
	ui.space(ui.SPACE_2)
	ui.next({width = ui.fill(), height = ui.children_sum()})
	if ui.row(.Center) {
		pen := int(s.sig.pen)
		if ui.segmented("###sign_pen", {i18n.tr("Ballpoint"), i18n.tr("Fountain pen"), i18n.tr("Felt pen"), i18n.tr("Brush")}, &pen) {
			s.sig.pen = Pen_Kind(pen)
			sign_pad_redo(s)
			sign_changed(app)
		}
		ui.spacer(ui.fill())
		if ui.button("sign_undo_stroke", icon = lucide.UNDO_2, o = {tip = i18n.tr("Remove the last stroke"), icon_font = ui.lucide_icons(), disabled = len(s.sig.strokes) == 0}).clicked {
			delete(pop(&s.sig.strokes))
			last := pop(&s.pad)
			draw.path_destroy(&last)
			sign_changed(app)
		}
		ui.space(ui.ICON_GAP)
		if ui.button("sign_clear", i18n.tr("Clear"), lucide.ERASER, {icon_font = ui.lucide_icons(), disabled = len(s.sig.strokes) == 0}).clicked {
			for t in s.sig.strokes { delete(t) }
			clear(&s.sig.strokes)
			sign_pad_redo(s)
			sign_changed(app)
		}
	}
	if ui.form_row(i18n.tr("Pen thickness")) {
		if ui.slider("###sign_thickness", &s.sig.thickness, 0.5, 2.5, 0.1, "%.1f", 1.2) {
			sign_pad_redo(s)
			sign_changed(app)
		}
	}
}

@(private = "file")
common_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	ui.next({width = ui.fill(), height = ui.children_sum()})
	if ui.row(.Center) {
		for c, i in SIGN_INKS {
			if swatch(fmt.tprintf("###sign_ink%d", i), {c[0], c[1], c[2], 255}, s.sig.ink == c, em, i18n.tr("Ink")) {
				s.sig.ink = c
				sign_changed(app)
			}
		}
		ui.space(ui.CONTROL_GAP)
		ui.next({width = ui.fill()})
		if ui.form_row(i18n.tr("Size")) {
			if ui.slider("###sign_scale", &s.sig.scale, 0.5, 2, 0.05, "%.2f×", 1) { sign_changed(app) }
		}
	}
	ui.next({width = ui.fill()})
	if ui.toggle("###sign_mention", i18n.tr("“Read and approved” above it"), &s.sig.mention) { sign_changed(app) }
	ui.next({width = ui.fill()})
	if ui.toggle("###sign_dated", i18n.tr("The place and the date under it"), &s.sig.dated) { sign_changed(app) }
	if s.sig.dated {
		ui.space(ui.SPACE_1)
		ui.next({width = ui.fill(), height = ui.children_sum()})
		if ui.row(.Center) {
			ui.next({width = ui.fill()})
			if ui.line_edit("###sign_where", &s.place, {placeholder = i18n.tr("Place")}).changed {
				delete(s.sig.place)
				s.sig.place = strings.clone(ui.line_edit_string(&s.place))
				sign_changed(app)
			}
			ui.space(ui.CONTROL_GAP)
			ui.next({width = ui.px(em * 9)})
			if ui.line_edit("###sign_when", &s.date, {placeholder = i18n.tr("Date")}).changed {
				delete(s.sig.date)
				s.sig.date = strings.clone(ui.line_edit_string(&s.date))
				sign_changed(app)
			}
		}
	}
}

// What a picture of the preview draws: paper, and the signature in the middle, as large as it fits.
@(private = "file")
Sign_Paper :: struct {
	tex:   render.Texture,
	px:    [2]int,
	has:   bool,
	edge:  draw.Color,
	scale: f32,
}

@(private = "file")
sign_paper_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Sign_Paper)(user)
	r := b.rect
	draw.rect(dc, r, draw.WHITE, radius = 4 * d.scale)
	draw.rect(dc, r, d.edge, radius = 4 * d.scale, border = d.scale)
	if !d.has { return }
	room := (r.max - r.min) - 12 * d.scale
	px := [2]f32{f32(d.px.x), f32(d.px.y)} / 2   // (rendered at twice the interface's scale: crisp)
	k := min(room.x / max(px.x, 1), room.y / max(px.y, 1), d.scale)
	size := px * k
	at := (r.min + r.max - size) / 2
	draw.image(dc, d.tex, {at, at + size})
}

@(private = "file")
preview_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	d := ui.frame_new(Sign_Paper)
	d.tex, d.px, d.has = s.tex, s.tex_size, s.tex_size != {} && s.preview != nil && s.preview.rgba != nil
	d.edge, d.scale = ui.color("border"), ui.scale()
	ui.next({width = ui.fill(), height = ui.px(em * 7)})
	b := ui.custom("###sign_preview", sign_paper_draw, d)
	if ui.a11y_wanted() { ui.a11y_set(b, {role = .Image, name = i18n.tr("The signature as it goes on the page")}) }
}

////////////////////////////////
// The pad

// What the pad draws: paper, a line to sign on, the ink.
@(private = "file")
Pad_Draw :: struct {
	strokes: []draw.Path,
	ink:     draw.Color,
	line:    draw.Color,
	edge:    draw.Color,
	scale:   f32,
}

@(private = "file")
pad_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Pad_Draw)(user)
	r := b.rect
	draw.rect(dc, r, draw.WHITE, radius = 4 * d.scale)
	draw.rect(dc, r, d.edge, radius = 4 * d.scale, border = d.scale)
	size := r.max - r.min
	k := size / SIGN_PAD
	y := r.min.y + size.y * 0.74
	x0, x1 := r.min.x + size.x * 0.06, r.max.x - size.x * 0.06
	draw.line(dc, {x0, y}, {x1, y}, d.scale, d.line)
	// (the cross where one signs, as on a form)
	c, h := [2]f32{x0 + 6 * d.scale, y - 9 * d.scale}, 4 * d.scale
	draw.line(dc, c - h, c + h, 1.5 * d.scale, d.line)
	draw.line(dc, {c.x - h, c.y + h}, {c.x + h, c.y - h}, 1.5 * d.scale, d.line)
	// (the outlines in the pad's units, scaled to the box: antialiased, the nib's width as the pen made it)
	draw.push_transform(dc, draw.affine_mul(draw.affine_translate(r.min), draw.affine_scale(k)))
	for &p in d.strokes { draw.path_fill(dc, &p, d.ink) }
	draw.pop_transform(dc)
}

@(private = "file")
pad_build :: proc(app: ^App, em: f32) {
	s := &app.sign
	d := ui.frame_new(Pad_Draw)
	d.strokes = s.pad[:]
	c := s.sig.ink
	d.ink = draw.srgb(f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255)
	d.line, d.edge, d.scale = draw.srgb(0.75, 0.77, 0.8), ui.color("border"), ui.scale()
	ui.next({width = ui.fill(), height = ui.px(em * 12)})
	b := ui.custom("###sign_pad", pad_draw, d, {.Clickable})
	b.cursor = .Crosshair
	if ui.a11y_wanted() { ui.a11y_set(b, {role = .Image, name = i18n.tr("Draw your signature here")}) }
	sig := ui.signal(b)
	size := b.rect.max - b.rect.min
	if size.x <= 0 || size.y <= 0 { return }
	at := [2]f32{clamp(sig.mouse.x / size.x, 0, 1), clamp(sig.mouse.y / size.y, 0, 1)} * SIGN_PAD
	now := ui.now_ms()
	if sig.pressed && !s.drawing {
		s.drawing, s.stroke_ms = true, now
		st := make(Stroke)
		append(&st, ink.Sample{at = at})
		append(&s.sig.strokes, st)
		append(&s.pad, draw.path_make())
		pad_stroke(s, len(s.sig.strokes) - 1)
	}
	if !s.drawing || len(s.sig.strokes) == 0 { return }
	st := &s.sig.strokes[len(s.sig.strokes) - 1]
	if sig.dragging {
		last := st[len(st) - 1].at
		if d := at - last; d.x * d.x + d.y * d.y >= SIGN_STEP * SIGN_STEP {
			append(st, ink.Sample{at = at, time = now - s.stroke_ms})
			pad_stroke(s, len(s.sig.strokes) - 1)
		}
		host.host_settle(&app.main)
	}
	if sig.released || (!sig.dragging && !sig.pressed) {
		s.drawing = false
		sign_changed(app)
	}
}

// The ink of stroke `i` of the pad, made again from its samples.
@(private = "file")
pad_stroke :: proc(s: ^Sign_State, i: int) {
	o := ink.outline(s.sig.strokes[i][:], sign_pen(s.sig), context.temp_allocator)
	poly := ink.polygon(o, context.temp_allocator)
	p := &s.pad[i]
	draw.path_clear(p)
	if len(poly) < 3 { return }
	draw.path_move_to(p, poly[0])
	for q in poly[1:] { draw.path_line_to(p, q) }
	draw.path_close(p)
}

// Every stroke's ink made again: a new pen.
sign_pad_redo :: proc(s: ^Sign_State) {
	for &p in s.pad { draw.path_destroy(&p) }
	clear(&s.pad)
	for _ in s.sig.strokes { append(&s.pad, draw.path_make()) }
	for _, i in s.sig.strokes { pad_stroke(s, i) }
}
