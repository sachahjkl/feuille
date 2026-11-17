package feuille

// The window, built each frame from the App: the bar, then the pages, the password asked, or the empty view. A frame
// reads the layout and the pictures; it computes nothing in proportion to the page count (src/md/features/viewer.md).

import "core:fmt"
import "core:math"
import "core:path/filepath"
import "gt:draw"
import host "gt:host"
import "gt:lucide"
import "gt:render"
import "gt:ui"
import pdf "pdf"

// The pages built beyond the view, above and below, in views' heights: their pictures are ready when they come in.
VIEW_AHEAD :: 1.0
// The vertical scroll bar's width and its gap, in logical pixels.
SCROLL_BAR_ROOM :: 16.0

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	app.frame += 1
	actions_keys(app)
	em := ui.font_size()
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.column() {
		bar(app, em)
		ui.next({width = ui.fill(), height = ui.fill()})
		if ui.column() {
			switch {
			case app.pending == .Locked: password_view(app, em)
			case app.snapshot == nil:    empty_view(app)
			case:                        pages_view(app, size)
			}
		}
	}
}

@(private = "file")
bar :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(em * 2.6)})
	if ui.row(.Center) {
		ui.space(ui.SPACE_2)
		action_button(app, .Open, "Open")
		ui.space(ui.SPACE_3)
		ui.next({width = ui.fill()})
		if ui.tags("weak") {
			name := app.snapshot != nil ? filepath.base(app.snapshot.path) : ""
			if app.pending == .Loading { name = fmt.tprintf("Opening %s…", filepath.base(app.asked)) }
			ui.label(fmt.tprintf("%s###name", name))
		}
		if app.snapshot != nil {
			action_button(app, .Layer, "", app.layer)
			ui.space(ui.SPACE_3)
			action_button(app, .Zoom_Out)
			ui.next({width = ui.px(em * 3.6)})
			ui.label(fmt.tprintf("%d %%###zoom", int(math.round(ui.zoom_zone_value(&app.zone) * 100))))
			action_button(app, .Zoom_In)
			action_button(app, .Fit)
		}
		ui.space(ui.SPACE_2)
	}
}

// A button for an act of the table: its glyph, its words when given, its label and key as its tip.
@(private = "file")
action_button :: proc(app: ^App, a: Action, text := "", lit := false) {
	c := ACTIONS[a]
	tip := c.label
	if k := ui.command_shortcut(c); k != "" { tip = fmt.tprintf("%s (%s)", c.label, k) }
	o := ui.Button_Options{tip = tip, icon_font = ui.lucide_icons(), disabled = !action_enabled(app, a), lit = lit}
	if ui.button(c.id, text, c.icon, o).clicked { action_run(app, a) }
}

@(private = "file")
empty_view :: proc(app: ^App) {
	e := ui.Empty_State{icon = lucide.FILE_TEXT, title = "Open a PDF", note = "Drop a file here, or press Ctrl+O. Signatures, annotations and form fields stay hidden.", actions = {{text = "Open a PDF", icon = lucide.FOLDER_OPEN, intent = .Primary}}}
	if app.failure != .None {
		e.icon = lucide.FILE_X
		e.title = fmt.tprintf("%s cannot be opened", filepath.base(app.failed))
		e.note = failure_text(app.failure)
	}
	if ui.empty_state("###empty", e) == 0 { action_run(app, .Open) }
}

failure_text :: proc(e: pdf.Error) -> string {
	switch e {
	case .None:       return ""
	case .File:       return "The file cannot be read."
	case .Format:     return "It is not a PDF, or it is damaged."
	case .Security:   return "Its protection is of a kind this program does not know."
	case .Password:   return "The password is wrong."
	case .No_Library: return "The PDF engine (libpdfium) is not installed."
	case .Unknown, .Page: return "The PDF engine refused it."
	}
	return ""
}

@(private = "file")
password_view :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.column(.Center) {
		ui.spacer(ui.fill())
		ui.next({width = ui.px(em * 22), height = ui.children_sum()})
		if ui.column() {
			ui.next({width = ui.fill()})
			ui.label(fmt.tprintf("%s is protected###locked", filepath.base(app.asked)))
			ui.space(ui.SPACE_3)
			ui.next({width = ui.fill()})
			field := ui.line_edit("###password", &app.password, {kind = .Secret, reveal = &app.reveal, placeholder = "Password"})
			if app.wrong {
				ui.space(ui.SPACE_2)
				ui.next({width = ui.fill()})
				if ui.tags("bad") { ui.label("Wrong password###wrong") }
			}
			ui.space(ui.SPACE_3)
			ui.next({width = ui.fill()})
			if ui.row() {
				ui.spacer(ui.fill())
				if ui.button("cancel", "Cancel").clicked || ui.key_press(.Escape) {
					app.pending = .None
					app.wrong = false
					ui.line_edit_clear(&app.password)
				}
				ui.space(ui.SPACE_2)
				open := ui.button("unlock", "Open", o = {intent = .Primary}).clicked || field.committed
				if open && app.pending == .Locked { app_open_file(app, app.asked, ui.line_edit_string(&app.password)) }
			}
		}
		ui.spacer(ui.fill())
	}
}

// What a page's box draws: its sheet, then its picture when it has one.
@(private = "file")
Page_Draw :: struct {
	tex:   render.Texture,
	has:   bool,
	paper: draw.Color,
}

@(private = "file")
page_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Page_Draw)(user)
	draw.rect(dc, b.rect, d.paper)
	if d.has { draw.image(dc, d.tex, b.rect) }
}

@(private = "file")
pages_view :: proc(app: ^App, window: host.Vec2) {
	s := app.snapshot
	zoom := ui.zoom_zone(&app.zone, s.path)
	ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
	box := ui.build_box({.Clip, .View_Scroll_X, .View_Scroll_Y, .View_Clamp_X, .View_Clamp_Y, .Allow_Overflow_X, .Allow_Overflow_Y}, "###pages")
	_ = ui.signal(box)
	if ui.parent(box) { pages_column(app, box, zoom, window) }
}

@(private = "file")
pages_column :: proc(app: ^App, box: ^ui.Box, zoom: f32, window: host.Vec2) {
	s := app.snapshot
	// the view's size, as the last layout found it (the window's before the first), less the vertical scroll bar's room:
	// a column fitted to the whole box would overflow it by the bar and scroll sideways
	view := [2]f32{box.rect.max.x - box.rect.min.x, box.rect.max.y - box.rect.min.y}
	if view.x <= 0 || view.y <= 0 { view = window }
	view.x = max(view.x - SCROLL_BAR_ROOM, 1)
	if app.to_top {
		box.view_off, box.view_target = {}, {}
		app.to_top = false
	}
	if layout_stale(app.layout, s.revision, view.x, zoom) {
		// (the point at the middle of the view stays there through a zoom or a resize)
		page, fraction := layout_at(app.layout, box.view_off.y + view.y / 2)
		same := app.layout.revision == s.revision && page >= 0
		layout_make(&app.layout, s.revision, s.pages, view.x, zoom, ui.scale())
		if same {
			y := app.layout.tops[page] + fraction * app.layout.sizes[page].y - view.y / 2
			box.view_off.y, box.view_target.y = max(y, 0), max(y, 0)
		}
	}
	l := &app.layout
	if len(l.tops) == 0 { return }
	width := max(view.x, l.widest + 2 * PAGE_MARGIN)
	top := box.view_off.y
	first, last := layout_range(l^, top - view.y * VIEW_AHEAD, top + view.y * (1 + VIEW_AHEAD))
	ask_pictures(app, first, last, top + view.y / 2)

	paper := draw.WHITE   // (a page's paper is white whatever the theme: the engine draws on white)
	ui.next({width = ui.px(width), height = ui.children_sum()})
	if ui.column() {
		ui.spacer(ui.px(l.tops[first]), exact = true)
		for i in first ..< last {
			if i > first { ui.spacer(ui.px(PAGE_GAP), exact = true) }
			p := s.pages[i]
			ui.next({width = ui.fill(), height = ui.px(l.sizes[i].y)})
			if ui.row() {
				ui.spacer(ui.fill())
				d := ui.frame_new(Page_Draw)
				d.paper = paper
				if shown, ok := &app.pictures[p.id]; ok {
					d.tex, d.has = shown.tex, true
					shown.seen = app.frame
				}
				ui.next({width = ui.px(l.sizes[i].x), height = ui.px(l.sizes[i].y)})
				ui.custom(fmt.tprintf("###page%d", p.id), page_draw, d)
				ui.spacer(ui.fill())
			}
		}
		below := l.height - (l.tops[last - 1] + l.sizes[last - 1].y)
		ui.spacer(ui.px(below), exact = true)
	}
}

// Asks the worker for the pictures of [first, last) that are missing or stale, the nearest to `middle` first. Nothing
// when the list is the one asked last.
@(private = "file")
ask_pictures :: proc(app: ^App, first, last: int, middle: f32) {
	s := app.snapshot
	l := &app.layout
	k := ui.scale()
	asks := make([dynamic]Render_Ask, 0, last - first, context.temp_allocator)
	for i in first ..< last {
		p := s.pages[i]
		size := [2]int{int(math.round(l.sizes[i].x * k)), int(math.round(l.sizes[i].y * k))}
		if size.x <= 0 || size.y <= 0 { continue }
		if shown, ok := app.pictures[p.id]; ok && shown.size == size && shown.layer == app.layer { continue }
		append(&asks, Render_Ask{revision = s.revision, index = i, id = p.id, size = size, layer = app.layer})
	}
	// nearest first (a handful of pages: an insertion sort)
	distance :: proc(l: ^Layout, i: int, middle: f32) -> f32 { return abs(l.tops[i] + l.sizes[i].y / 2 - middle) }
	for i in 1 ..< len(asks) {
		for j := i; j > 0 && distance(l, asks[j].index, middle) < distance(l, asks[j - 1].index, middle); j -= 1 {
			asks[j], asks[j - 1] = asks[j - 1], asks[j]
		}
	}
	if len(asks) == 0 || same_asks(asks[:], app.last_ask[:]) { return }
	clear(&app.last_ask)
	append(&app.last_ask, ..asks[:])
	worker_render(&app.worker, asks[:])
}

@(private = "file")
same_asks :: proc(a, b: []Render_Ask) -> bool {
	if len(a) != len(b) { return false }
	for x, i in a { if x != b[i] { return false } }
	return true
}
