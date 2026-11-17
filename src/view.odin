package feuille

// The window, built each frame from the App: the title bar (the window's own: its tools, the settings, close), the last
// crash's bar, then the pages, the settings, the password asked or the empty view, and the status bar. A frame reads
// the layout and the pictures; it computes nothing in proportion to the page count (src/md/features/viewer.md).

import "core:fmt"
import "core:math"
import "core:path/filepath"
import crash_bar "gt:crash_bar"
import "gt:draw"
import host "gt:host"
import i18n "gt:i18n"
import lucide "gt:lucide"
import prefs_page "gt:prefs_page"
import "gt:render"
import "gt:ui"
import pdf "pdf"

// The pages built beyond the view, above and below, in views' heights: their pictures are ready when they come in.
VIEW_AHEAD :: 1.0
// The vertical scroll bar's width and its gap, in logical pixels: the column fits beside it.
SCROLL_BAR_ROOM :: 16.0
// The heights of the bars, in ems.
TOOL_EM   :: 2.1
STATUS_EM :: 1.9
// Logical pixels past the machined halo's reach before the title bar's rule.
HALO_ROOM_PX :: 2

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	app.frame += 1
	em := ui.font_size()
	// (the user's themes file: a task looks at it now and then; app_params shows what it read)
	if prefs_page.themes_file_poll(&app.themes_file, &h.state) { host.host_settle(h) }
	// (the dialogs and the views: the palette, the keys' sheet, around and over the page)
	if ui.views_frame(&app.views) {
		window_keys(app)
		if app.settings_open { settings_keys(app) } else { actions_keys(app) }
		actions_build(app)
		ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
		page := ui.build_box({.Draw_Background}, "###page")
		if ui.parent(page) { build_page(app, em, size) }
	}
}

@(private = "file")
build_page :: proc(app: ^App, em: f32, window: host.Vec2) {
	build_title(app, em)
	ui.hline(ui.fill())
	crash_bar.bar(&app.crash_bar, {name = APP_TITLE, version = APP_VERSION, repository = "sachahjkl/feuille"})
	ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
	if ui.column() {
		switch {
		case app.settings_open:        settings_build(app)
		case app.pending == .Locked:   password_view(app, em)
		case app.snapshot == nil:      empty_view(app)
		case:                          pages_view(app, window)
		}
	}
	ui.hline(ui.fill())
	build_status(app, em)
}

// An icon of Lucide, `width` wide.
@(private = "file")
glyph :: proc(g: string, width: f32, fg: Maybe(ui.Color) = nil, size: f32 = 0) {
	ui.next({width = ui.px(width), height = ui.pct(1), font = ui.lucide_icons(), font_size = size > 0 ? size : ui.font_size(), text_align = .Center, fg = fg})
	ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###g%d", g, ui.parent_box().child_count))
}

// A tool of the title bar for an action of the table: its glyph, its label and keys as its tip, its act name (the
// palette's Shift+Enter on the action comes to it). `lit`: a switch that is on.
@(private = "file")
tool :: proc(app: ^App, a: Action, em: f32, lit := false) {
	c := ACTIONS[a]
	ui.next({width = ui.px(em * TOOL_EM), height = ui.px(em * TOOL_EM), radius = em * 0.4})
	sig := ui.button(c.id, icon = c.icon, o = {tip = ui.command_tip(c), icon_font = ui.lucide_icons(), disabled = !action_enabled(app, a), lit = lit})
	ui.act_command(sig.box, c.id)
	if sig.clicked { action_run(app, a) }
}

@(private = "file")
build_title :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * TOOL_EM) + 2 * (ui.MACHINED_OVERFLOW_PX + HALO_ROOM_PX) * ui.scale())})
	if ui.title_bar("###titlebar") {
		ui.space(ui.SPACE_2)
		glyph(lucide.LEAF, em * 1.8, ui.color("accent"), em * 1.3)
		ui.space(ui.ICON_GAP)
		// the title: what is open; its empty part moves the window
		title := APP_TITLE
		switch {
		case app.settings_open:          title = i18n.tr("Settings")
		case app.pending == .Loading:    title = fmt.tprintf(i18n.tr("Opening %s…"), filepath.base(app.asked))
		case app.snapshot != nil:        title = filepath.base(app.snapshot.path)
		}
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###title", title))
		if app.settings_open {
			ui.next({width = ui.px(em * TOOL_EM), height = ui.px(em * TOOL_EM), radius = em * 0.4})
			if ui.button("back", icon = lucide.ARROW_LEFT, o = {tip = ui.key_tip(i18n.tr("Back to the document"), {.Escape, {}}), icon_font = ui.lucide_icons()}).clicked { app.settings_open = false }
		} else {
			if app.snapshot != nil {
				tool(app, .Layer, em, app.layer)
				ui.space(ui.CONTROL_GAP)
				tool(app, .Zoom_Out, em)
				ui.next({width = ui.text_size(em * 0.4), height = ui.pct(1), text_align = .Center})
				if ui.tags("weak") { ui.label(fmt.tprintf("%d %%###zoom", int(math.round(ui.zoom_zone_value(&app.zone) * 100)))) }
				tool(app, .Zoom_In, em)
				tool(app, .Fit, em)
				ui.space(ui.CONTROL_GAP)
			}
			tool(app, .Open, em)
			tool(app, .Settings, em)
		}
		// (the system's title bar has its own close button)
		if !app.settings.system_title {
			ui.space(ui.TOOL_GAP)
			ui.next({width = ui.px(em * TOOL_EM), height = ui.px(em * TOOL_EM), radius = em * 0.4})
			if ui.button("close", icon = lucide.X, o = {tip = ui.command_tip(ACTIONS[.Quit]), icon_font = ui.lucide_icons()}).clicked { app.quit = true }
		}
		ui.space(ui.SPACE_2)
	}
}

@(private = "file")
build_status :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * STATUS_EM))})
	if ui.row(.Center) {
		ui.space(ui.SPACE_3)
		// (an update on offer, coming or in place: a button to act on it)
		ui.next({height = ui.px(ui.dense(em * (STATUS_EM - 0.45)))})
		if b := prefs_page.update_badge(app.updates.updater, proc(user: rawptr) { app_restart((^App)(user)) }, app); b != nil {
			ui.space(ui.CONTROL_GAP)
		}
		if ui.style({font_size = em * 0.88}) {
			if ui.tags("weak") {
				msg := app.status
				if msg == "" || ui.now_ms() > app.status_until {
					msg = ""
					if s := app.snapshot; s != nil && !app.settings_open {
						msg = fmt.tprintf(i18n.tr("Page %d of %d"), app.current + 1, len(s.pages))
						if !app.layer { msg = fmt.tprintf("%s · %s", msg, i18n.tr("form layer hidden")) }
					}
				}
				ui.next({width = ui.fill(), flags = {.Selectable}})
				ui.label(fmt.tprintf("%s###status", msg))
				ui.kbd("Ctrl+K")
				ui.space(ui.SPACE_1)
				ui.label(fmt.tprintf("%s###palette_hint", i18n.tr("Commands")))
			}
		}
		ui.space(ui.SPACE_3)
	}
}

@(private = "file")
empty_view :: proc(app: ^App) {
	e := ui.Empty_State{icon = lucide.FILE_TEXT, title = i18n.tr("Open a PDF"), note = i18n.tr("Drop a file here, or press Ctrl+O. Signatures, annotations and form fields stay hidden."), actions = {{text = i18n.tr("Open a PDF"), icon = lucide.FOLDER_OPEN, intent = .Primary}}}
	if app.failure != .None {
		e.icon = lucide.FILE_X
		e.title = fmt.tprintf(i18n.tr("%s cannot be opened"), filepath.base(app.failed))
		e.note = failure_text(app.failure)
	}
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.empty_state("###empty", e) == 0 { action_run(app, .Open) }
}

failure_text :: proc(e: pdf.Error) -> string {
	switch e {
	case .None:           return ""
	case .File:           return i18n.tr("The file cannot be read.")
	case .Format:         return i18n.tr("It is not a PDF, or it is damaged.")
	case .Security:       return i18n.tr("Its protection is of a kind this program does not know.")
	case .Password:       return i18n.tr("The password is wrong.")
	case .No_Library:     return i18n.tr("The PDF engine (libpdfium) is not installed.")
	case .Unknown, .Page: return i18n.tr("The PDF engine refused it.")
	}
	return ""
}

@(private = "file")
password_view :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.column(.Center) {
		ui.spacer(ui.fill())
		ui.next({width = ui.px(em * 24), height = ui.children_sum()})
		if ui.column() {
			ui.next({width = ui.fill(), height = ui.px(em * 3), font = ui.lucide_icons(), font_size = em * 2.4, text_align = .Center})
			if ui.tags("weak") { ui.build_box({.Draw_Text, .No_Text_Trunc}, lucide.LOCK_KEYHOLE + "###lock") }
			ui.space(ui.SPACE_3)
			ui.next({width = ui.fill(), text_align = .Center})
			ui.label(fmt.tprintf("%s###locked", fmt.tprintf(i18n.tr("%s is protected"), filepath.base(app.asked))))
			ui.space(ui.SPACE_3)
			ui.next({width = ui.fill()})
			field := ui.line_edit("###password", &app.password, {kind = .Secret, reveal = &app.reveal, placeholder = i18n.tr("Password")})
			// (the keyboard in the field each time the password is asked: the person types at once)
			if app.focus_password {
				ui.set_focus(field.box.key)
				app.focus_password = false
			}
			if app.wrong {
				ui.space(ui.SPACE_2)
				ui.next({width = ui.fill()})
				if ui.tags("bad") { ui.label(fmt.tprintf("%s###wrong", i18n.tr("Wrong password"))) }
			}
			ui.space(ui.SPACE_3)
			ui.next({width = ui.fill(), height = ui.children_sum()})
			if ui.row() {
				ui.spacer(ui.fill())
				if ui.button("cancel", i18n.tr("Cancel")).clicked || ui.key_press(.Escape) {
					app.pending = .None
					app.wrong = false
					ui.line_edit_clear(&app.password)
				}
				ui.space(ui.CONTROL_GAP)
				open := ui.button("unlock", i18n.tr("Open"), o = {intent = .Primary}).clicked || field.committed
				if open && app.pending == .Locked { app_open_file(app, app.asked, ui.line_edit_string(&app.password)) }
			}
		}
		ui.spacer(ui.fill())
	}
}

// What a page's box draws: its sheet and a soft shadow, then its picture when it has one.
@(private = "file")
Page_Draw :: struct {
	tex:    render.Texture,
	has:    bool,
	shadow: draw.Color,
	scale:  f32,
}

@(private = "file")
page_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Page_Draw)(user)
	lift := 2 * d.scale
	draw.rect(dc, {b.rect.min + {0, lift}, b.rect.max + {0, lift}}, d.shadow, soft = 6 * d.scale)
	draw.rect(dc, b.rect, draw.WHITE)   // (a page's paper is white whatever the theme: the engine draws on white)
	if d.has { draw.image(dc, d.tex, b.rect) }
}

@(private = "file")
pages_view :: proc(app: ^App, window: host.Vec2) {
	zoom := ui.zoom_zone(&app.zone, app.snapshot.path)
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
			y := max(app.layout.tops[page] + fraction * app.layout.sizes[page].y - view.y / 2, 0)
			box.view_off.y, box.view_target.y = y, y
		}
	}
	l := &app.layout
	if len(l.tops) == 0 { return }
	if app.go_to >= 0 && app.go_to < len(l.tops) {
		box.view_target.y = max(l.tops[app.go_to] - PAGE_MARGIN, 0)
	}
	app.go_to = -1
	top := box.view_off.y
	app.current, _ = layout_at(l^, top + view.y / 2)
	first, last := layout_range(l^, top - view.y * VIEW_AHEAD, top + view.y * (1 + VIEW_AHEAD))
	ask_pictures(app, first, last, top + view.y / 2)
	if first >= last { return }

	shadow := ui.color("shadow")
	ui.next({width = ui.px(max(view.x, l.widest + 2 * PAGE_MARGIN)), height = ui.children_sum()})
	if ui.column() {
		ui.spacer(ui.px(l.tops[first]), exact = true)
		for i in first ..< last {
			if i > first { ui.spacer(ui.px(PAGE_GAP), exact = true) }
			p := s.pages[i]
			ui.next({width = ui.fill(), height = ui.px(l.sizes[i].y)})
			if ui.row() {
				ui.spacer(ui.fill())
				d := ui.frame_new(Page_Draw)
				d.shadow, d.scale = shadow, ui.scale()
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
	asks := make([dynamic]Render_Ask, 0, max(last - first, 0), context.temp_allocator)
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
