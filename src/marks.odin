package feuille

// The marking tools (src/md/features/marks.md): text and shapes put on a page. One tool at a time; with one on, a press
// on a page draws a shape, places a text, or takes the mark under it (a drag moves it, a click on a text opens it).
// The marks' places come from the snapshot (shares of the page shown): nothing here calls the engine.

import "core:fmt"
import "core:math"
import "gt:draw"
import "gt:host"
import i18n "gt:i18n"
import lucide "gt:lucide"
import pdf "gt:pdf"
import "gt:render"
import "gt:ui"

Tool :: enum u8 { None, Text, Rect, Ellipse, Line, Arrow, Pen, Highlight, Signature }

Mark_Kind :: enum u8 { None, Stamp, Shape }

// A mark of a page: its page, its kind, its index among the page's stamps or shapes.
Mark_Ref :: struct {
	id:    u64,
	kind:  Mark_Kind,
	index: int,
}

// A press on a page with a tool on, until its release: where it started and where it is (shares of the page shown),
// the mark it took (none: it draws), the Pen's points, and whether it moved far enough to be a drag.
Gesture :: struct {
	active: bool,
	id:     u64,
	start:  [2]f32,
	now:    [2]f32,
	on:     Mark_Ref,
	points: [dynamic][2]f32,
	moved:  bool,
}

// How far a press goes before it is a drag, in pixels: below, a click.
DRAG_SLOP_PX :: 4
// The Pen keeps a point when the pointer went this far from the last one, in pixels: a line, not a cloud.
PEN_STEP_PX :: 2
// A mark is hit this close to its box, in pixels: a thin line can be taken.
HIT_SLOP_PX :: 5

// The tools' styles before anything is chosen: a red line of 2 points, no fill; a yellow highlighter.
SHAPE_STYLE :: pdf.Shape{stroke = {220, 38, 38, 255}, width = 2}
HIGHLIGHT_INK :: [4]u8{253, 224, 71, 110}

text_tool :: proc(app: ^App) -> bool { return app.tool == .Text }

// The tool on, or off when it already was. Leaving a tool commits what was being written and lets the mark go.
tool_toggle :: proc(app: ^App, t: Tool) {
	text_edit_commit(app)
	app.chosen = {}
	app.tool = app.tool == t ? .None : t
	switch app.tool {
	case .None:
	case .Text: say(app, i18n.tr("Click where the text goes, or on a text to change it; Escape leaves"))
	case .Rect, .Ellipse, .Line, .Arrow, .Pen, .Highlight:
		say(app, i18n.tr("Drag on the page to draw; drag a mark to move it, Delete removes it; Escape leaves"))
	case .Signature:
		// (the signature kept, to change or to place at once)
		sign_open(app)
	}
	if app.tool != .Signature { ui.view_close(&app.views, SIGN_VIEW) }
}

// The mark of page `p` under `at` (shares), texts first (they are drawn over the shapes), the last drawn first; the
// slop in shares of the page's size `size` (pixels).
mark_at :: proc(p: Snapshot_Page, at: [2]f32, size: [2]f32) -> Mark_Ref {
	slop := [2]f32{HIT_SLOP_PX / max(size.x, 1), HIT_SLOP_PX / max(size.y, 1)} * ui.scale()
	inside :: proc(b: [4]f32, at, slop: [2]f32) -> bool {
		return at.x >= b[0] - slop.x && at.x <= b[2] + slop.x && at.y >= b[1] - slop.y && at.y <= b[3] + slop.y
	}
	#reverse for st, k in p.stamps { if inside(st.box, at, {}) { return {p.id, .Stamp, k} } }
	#reverse for sh, k in p.shapes { if inside(sh.box, at, slop) { return {p.id, .Shape, k} } }
	return {}
}

// The style a new shape of the tool takes.
@(private = "file")
tool_style :: proc(app: ^App) -> pdf.Shape {
	s := app.ink
	#partial switch app.tool {
	case .Rect:      s.kind = .Rect
	case .Ellipse:   s.kind = .Ellipse
	case .Line:      s.kind = .Line
	case .Arrow:     s.kind = .Arrow
	case .Pen:       s.kind = .Ink; s.fill = {}
	case .Highlight: s = {kind = .Rect, fill = app.marker}
	}
	if s.kind == .Line || s.kind == .Arrow { s.fill = {} }
	return s
}

// A press, a drag and a release of a tool on page `p`, laid out `size` pixels; `sig` its box's signal.
marks_input :: proc(app: ^App, p: Snapshot_Page, sig: ui.Signal, size: [2]f32) {
	g := &app.gesture
	at := [2]f32{clamp(sig.mouse.x / max(size.x, 1), 0, 1), clamp(sig.mouse.y / max(size.y, 1), 0, 1)}
	if app.tool == .Signature && sig.hovering { app.sign.hover = {p.id, at, app.frame} }
	if sig.pressed && !g.active {
		text_edit_commit(app)
		clear(&g.points)
		g.active, g.id, g.start, g.now, g.moved = true, p.id, at, at, false
		g.on = mark_at(p, at, size)
		app.chosen = g.on
		if app.tool == .Pen && g.on.kind == .None { append(&g.points, at) }
	}
	if !g.active || g.id != p.id { return }
	if sig.dragging {
		g.now = at
		d := (g.now - g.start) * size
		if d.x * d.x + d.y * d.y > DRAG_SLOP_PX * DRAG_SLOP_PX * ui.scale() * ui.scale() { g.moved = true }
		if app.tool == .Pen && g.on.kind == .None && len(g.points) > 0 {
			last := (g.points[len(g.points) - 1] - at) * size
			if last.x * last.x + last.y * last.y >= PEN_STEP_PX * PEN_STEP_PX * ui.scale() * ui.scale() { append(&g.points, at) }
		}
		host.host_settle(&app.main)
	}
	if sig.released || (!sig.dragging && !sig.pressed) { gesture_end(app, p) }
}

// The gesture's end: a mark moved, a text opened, a shape made, a text placed.
@(private = "file")
gesture_end :: proc(app: ^App, p: Snapshot_Page) {
	g := &app.gesture
	defer { g.active = false; clear(&g.points) }
	w := &app.worker
	delta := g.now - g.start
	switch g.on.kind {
	case .Stamp:
		if g.on.index >= len(p.stamps) { return }
		st := p.stamps[g.on.index]
		if g.moved {
			style := st.stamp
			style.text = ""
			at := [2]f32{st.box[0], st.box[1]} + delta
			worker_edit(w, stamp_ask_make(w, p.id, g.on.index, style, st.stamp.text, at, moved = true))
		} else if app.tool == .Text {
			stamp_click(app, p, g.start)
		}
	case .Shape:
		if !g.moved || g.on.index >= len(p.shapes) { return }
		sh := p.shapes[g.on.index]
		points := make([][2]f32, len(sh.shape.points), context.temp_allocator)
		for q, k in sh.shape.points { points[k] = q + delta }
		style := sh.shape
		style.points = nil
		worker_edit(w, shape_ask_make(w, p.id, g.on.index, style, points))
	case .None:
		switch app.tool {
		case .None:
		case .Text:
			if !g.moved { stamp_click(app, p, g.start) }
		case .Pen:
			if len(g.points) >= 2 { worker_edit(w, shape_ask_make(w, p.id, -1, tool_style(app), g.points[:])) }
		case .Rect, .Ellipse, .Line, .Arrow, .Highlight:
			if g.moved { worker_edit(w, shape_ask_make(w, p.id, -1, tool_style(app), {g.start, g.now})) }
		case .Signature:
			if !g.moved { sign_place(app, p, g.start) }
		}
	}
}

// Delete: the chosen mark goes.
mark_remove :: proc(app: ^App) -> bool {
	c := app.chosen
	if c.kind == .None || app.text.open { return false }
	w := &app.worker
	switch c.kind {
	case .Stamp: worker_edit(w, stamp_ask_make(w, c.id, c.index, {}, ""))
	case .Shape: worker_edit(w, shape_ask_make(w, c.id, c.index, {}, remove = true))
	case .None:
	}
	app.chosen = {}
	return true
}

// The chosen mark, as the snapshot has it; ok false: it is gone (an undo, another edit).
@(private = "file")
chosen_of :: proc(app: ^App) -> (p: Snapshot_Page, ok: bool) {
	c := app.chosen
	if c.kind == .None || app.snapshot == nil { return }
	for q in app.snapshot.pages {
		if q.id != c.id { continue }
		if c.kind == .Stamp && c.index < len(q.stamps) { return q, true }
		if c.kind == .Shape && c.index < len(q.shapes) { return q, true }
	}
	return
}

// A change of the style bar while a mark is chosen: the mark takes it at once.
@(private = "file")
style_changed :: proc(app: ^App) {
	p, ok := chosen_of(app)
	if !ok || app.text.open { return }
	c := app.chosen
	w := &app.worker
	switch c.kind {
	case .Stamp:
		st := p.stamps[c.index]
		style := app.style
		style.text = ""
		worker_edit(w, stamp_ask_make(w, c.id, c.index, style, st.stamp.text))
	case .Shape:
		old := p.shapes[c.index].shape
		if old.kind == .Outline { return }   // (a signature's ink: its colour is the signature tool's)
		style := app.ink
		if old.kind == .Rect && old.stroke[3] == 0 && old.fill[3] > 0 && old.fill[3] < 255 { style = {fill = app.marker} }
		if old.kind == .Line || old.kind == .Arrow || old.kind == .Ink { style.fill = {} }
		worker_edit(w, shape_ask_make(w, c.id, c.index, style))
	case .None:
	}
}

////////////////////////////////
// The style bar

// The tool's style, while one is on; it applies to the chosen mark and to the next ones.
marks_style_bar :: proc(app: ^App, em: f32) {
	ui.space(ui.CONTROL_GAP)
	changed := false
	#partial switch app.tool {
	case .Text:
		s := &app.style
		family := int(s.font.family)
		ui.next({height = ui.px(em * TOOL_EM)})
		if ui.segmented("###stamp_family", {i18n.tr("Sans"), i18n.tr("Serif"), i18n.tr("Mono")}, &family) { s.font.family = pdf.Family(family); changed = true }
		ui.space(ui.ICON_GAP)
		changed |= style_toggle("stamp_bold", lucide.BOLD, i18n.tr("Bold"), &s.font.bold, em)
		changed |= style_toggle("stamp_italic", lucide.ITALIC, i18n.tr("Italic"), &s.font.italic, em)
		ui.space(ui.ICON_GAP)
		size := int(s.size)
		ui.next({width = ui.px(em * 7.5), height = ui.px(em * TOOL_EM)})
		if ui.number("###stamp_size", &size, 4, 144, unit = "pt") { s.size = f32(size); changed = true }
		ui.space(ui.CONTROL_GAP)
		for c, i in INKS {
			if swatch(fmt.tprintf("###ink%d", i), {c[0], c[1], c[2], 255}, s.color == c, em, i18n.tr("Text colour")) { s.color = c; changed = true }
		}
		ui.space(ui.ICON_GAP)
		for c, i in GROUNDS {
			if swatch(fmt.tprintf("###ground%d", i), c, s.background == c, em, i18n.tr("Background")) { s.background = c; changed = true }
		}
	case .Signature:
		ui.next({width = ui.px(em * TOOL_EM), height = ui.px(em * TOOL_EM), radius = em * 0.4})
		if ui.button("sign_change", icon = lucide.FILE_PEN_LINE, o = {tip = i18n.tr("Change the signature…"), icon_font = ui.lucide_icons()}).clicked { sign_open(app) }
		ui.space(ui.CONTROL_GAP)
		for c, i in SIGN_INKS {
			if swatch(fmt.tprintf("###sign_bar_ink%d", i), {c[0], c[1], c[2], 255}, app.sign.sig.ink == c, em, i18n.tr("Ink")) { sign_ink_set(app, c) }
		}
	case .Highlight:
		for c, i in MARKERS {
			if swatch(fmt.tprintf("###marker%d", i), c, app.marker == c, em, i18n.tr("Highlighter colour")) { app.marker = c; changed = true }
		}
	case .Rect, .Ellipse, .Line, .Arrow, .Pen:
		s := &app.ink
		for c, i in LINES {
			if swatch(fmt.tprintf("###line%d", i), c, s.stroke == c, em, i18n.tr("Line colour")) { s.stroke = c; changed = true }
		}
		ui.space(ui.ICON_GAP)
		width := int(s.width)
		ui.next({width = ui.px(em * 7.5), height = ui.px(em * TOOL_EM)})
		if ui.number("###shape_width", &width, 1, 24, unit = "pt") { s.width = f32(width); changed = true }
		if app.tool == .Rect || app.tool == .Ellipse {
			ui.space(ui.ICON_GAP)
			for c, i in FILLS {
				if swatch(fmt.tprintf("###fill%d", i), c, s.fill == c, em, i18n.tr("Fill")) { s.fill = c; changed = true }
			}
		}
	}
	if changed { style_changed(app) }
}

@(private = "file")
style_toggle :: proc(id, glyph, tip: string, on: ^bool, em: f32) -> bool {
	ui.next({width = ui.px(em * TOOL_EM), height = ui.px(em * TOOL_EM), radius = em * 0.4})
	if ui.button(id, icon = glyph, o = {tip = tip, icon_font = ui.lucide_icons(), lit = on^}).clicked {
		on^ = !on^
		return true
	}
	return false
}

// The colours of the tools (alpha 0: none; under 255: a highlighter's, multiplied with the page).
@(private = "file", rodata) INKS := [?][3]u8{{0, 0, 0}, {29, 78, 216}, {185, 28, 28}, {255, 255, 255}}
@(private = "file", rodata) GROUNDS := [?][4]u8{{0, 0, 0, 0}, {255, 255, 255, 255}, {253, 230, 138, 255}, {0, 0, 0, 255}}
@(private = "file", rodata) LINES := [?][4]u8{{220, 38, 38, 255}, {29, 78, 216, 255}, {22, 163, 74, 255}, {0, 0, 0, 255}, {255, 255, 255, 255}}
@(private = "file", rodata) FILLS := [?][4]u8{{0, 0, 0, 0}, {255, 255, 255, 255}, {253, 230, 138, 255}, {0, 0, 0, 255}}
@(private = "file", rodata) MARKERS := [?][4]u8{{253, 224, 71, 110}, {134, 239, 172, 110}, {249, 168, 212, 110}, {125, 211, 252, 110}}

@(private = "file")
Swatch_Draw :: struct {
	color:  draw.Color,
	chosen: bool,
	none:   bool,   // the colour "none": a white square with a red diagonal
	accent: draw.Color,
	edge:   draw.Color,
	scale:  f32,
}

@(private = "file")
swatch_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Swatch_Draw)(user)
	r := b.rect
	inset := 4 * d.scale
	inner := draw.Rect{r.min + inset, r.max - inset}
	draw.rect(dc, inner, draw.WHITE, radius = 2 * d.scale)
	if d.none {
		draw.line(dc, {inner.min.x, inner.max.y}, {inner.max.x, inner.min.y}, 1.5 * d.scale, {0.8, 0.1, 0.1, 1})
	} else {
		draw.rect(dc, inner, d.color, radius = 2 * d.scale)
	}
	draw.rect(dc, inner, d.edge, radius = 2 * d.scale, border = d.scale)
	if d.chosen { draw.rect(dc, r, d.accent, radius = 3 * d.scale, border = 2 * d.scale) }
}

// A colour to choose: a square of it (on white, as on the page), ringed when chosen; true when clicked.
swatch :: proc(id: string, c: [4]u8, chosen: bool, em: f32, tip: string) -> bool {
	d := ui.frame_new(Swatch_Draw)
	d.color = draw.srgb(f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, f32(c[3]) / 255)
	d.chosen, d.none, d.scale = chosen, c[3] == 0, ui.scale()
	d.accent, d.edge = ui.color("accent"), ui.color("border")
	ui.next({width = ui.px(em * 1.6), height = ui.px(em * 1.6)})
	b := ui.custom(id, swatch_draw, d, {.Clickable})
	if ui.a11y_wanted() { ui.a11y_set(b, {role = .Button, name = tip, selected = chosen}) }
	return ui.signal(b).clicked
}

////////////////////////////////
// What a page draws over its picture

// The marks' outlines with a tool on, the chosen one, and what the gesture draws (frame memory; shares of the page).
Marks_Overlay :: struct {
	boxes:   [][4]f32,
	chosen:  [4]f32,
	has_chosen: bool,
	shift:   [2]f32,      // the chosen mark dragged by this much
	preview: Tool,        // a shape being drawn (None: none)
	from, to: [2]f32,
	points:  [][2]f32,    // the Pen's
	color:   draw.Color,
	accent:  draw.Color,
	ghost:   [4]f32,      // the signature's picture under the pointer (shares; has_ghost)
	has_ghost: bool,
	ghost_tex: render.Texture,
}

// The overlay of page `p` this frame (nil: nothing to draw).
marks_overlay :: proc(app: ^App, p: Snapshot_Page) -> ^Marks_Overlay {
	if app.tool == .None && app.chosen.kind == .None { return nil }
	if app.tool == .Signature && app.sign.hover.id == p.id { host.host_settle(&app.main) }
	o := ui.frame_new(Marks_Overlay)
	o.accent = ui.color("accent")
	if app.tool != .None {
		o.boxes = make([][4]f32, len(p.stamps) + len(p.shapes), context.temp_allocator)
		for st, k in p.stamps { o.boxes[k] = st.box }
		for sh, k in p.shapes { o.boxes[len(p.stamps) + k] = sh.box }
	}
	c := app.chosen
	if c.id == p.id {
		if c.kind == .Stamp && c.index < len(p.stamps) { o.chosen, o.has_chosen = p.stamps[c.index].box, true }
		if c.kind == .Shape && c.index < len(p.shapes) { o.chosen, o.has_chosen = p.shapes[c.index].box, true }
	}
	// (the signature follows the pointer: its picture where a click puts it, margin included)
	if h := app.sign.hover; app.tool == .Signature && h.id == p.id && h.frame + 1 >= app.frame && !app.gesture.active {
		if m := sign_ready_marks(app); m != nil && app.sign.tex_size != {} && p.size.x > 0 && p.size.y > 0 {
			half := (m.size / 2 + SIGN_PREVIEW_MARGIN) / p.size
			o.ghost, o.has_ghost, o.ghost_tex = {h.at.x - half.x, h.at.y - half.y, h.at.x + half.x, h.at.y + half.y}, true, app.sign.tex
		}
	}
	g := &app.gesture
	if g.active && g.id == p.id {
		if g.on.kind != .None && g.moved { o.shift = g.now - g.start }
		if g.on.kind == .None && app.tool >= .Rect {
			o.preview, o.from, o.to = app.tool, g.start, g.now
			o.points = g.points[:]
			s := tool_style(app)
			ink := s.stroke[3] > 0 ? s.stroke : s.fill
			o.color = draw.srgb(f32(ink[0]) / 255, f32(ink[1]) / 255, f32(ink[2]) / 255, max(f32(ink[3]) / 255, 0.5))
		}
	}
	return o
}

// Draws the overlay over the page's rectangle `r`.
marks_overlay_draw :: proc(dc: ^draw.Context, r: draw.Rect, o: ^Marks_Overlay, scale: f32) {
	if o == nil { return }
	size := r.max - r.min
	to_px :: proc(r: draw.Rect, size, q: [2]f32) -> [2]f32 { return r.min + q * size }
	box_px :: proc(r: draw.Rect, size: [2]f32, b: [4]f32) -> draw.Rect { return {r.min + {b[0], b[1]} * size, r.min + {b[2], b[3]} * size} }
	faint := o.accent
	faint.a = 0.45
	for b in o.boxes { draw.rect(dc, draw.rect_pad(box_px(r, size, b), 2 * scale), faint, border = scale) }
	// (the ink alone, a little faint until placed: the words under it stay seen)
	if o.has_ghost { draw.image(dc, o.ghost_tex, box_px(r, size, o.ghost), tint = {1, 1, 1, 0.75}) }
	if o.has_chosen {
		draw.rect(dc, draw.rect_shift(draw.rect_pad(box_px(r, size, o.chosen), 3 * scale), o.shift * size), o.accent, border = 2 * scale)
	}
	a, b := to_px(r, size, o.from), to_px(r, size, o.to)
	lo, hi := [2]f32{min(a.x, b.x), min(a.y, b.y)}, [2]f32{max(a.x, b.x), max(a.y, b.y)}
	w := 2 * scale
	#partial switch o.preview {
	case .Rect:      draw.rect(dc, {lo, hi}, o.color, border = w)
	case .Highlight: draw.rect(dc, {lo, hi}, o.color)
	case .Line, .Arrow: draw.line(dc, a, b, w, o.color)
	case .Ellipse:
		c, rad := (lo + hi) / 2, (hi - lo) / 2
		ring := make([][2]f32, 49, context.temp_allocator)
		for k in 0 ..= 48 {
			t := f32(k) / 48 * 2 * math.PI
			ring[k] = c + {math.cos(t), math.sin(t)} * rad
		}
		draw.polyline(dc, ring, w, o.color)
	case .Pen:
		if len(o.points) >= 2 {
			pts := make([][2]f32, len(o.points), context.temp_allocator)
			for q, k in o.points { pts[k] = to_px(r, size, q) }
			draw.polyline(dc, pts, w, o.color)
		}
	}
}
