package feuille

// The window, built each frame from the App: the title bar (the window's own), the tools of the document, the last
// crash's bar, then the thumbnails and the pages (or the settings, the password asked, the empty view), and the status
// bar. A frame reads the layouts and the pictures; it computes nothing in proportion to the page count
// (src/md/features/viewer.md). The pictures it wants, pages and thumbnails, go to the worker as one list at its end.

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
import pdf "gt:pdf"

// The pages built beyond the view, above and below, in views' heights: their pictures are ready when they come in.
VIEW_AHEAD :: 1.0
// The vertical scroll bar's width and its gap, in logical pixels: the column fits beside it.
SCROLL_BAR_ROOM :: 16.0
// The heights of the bars, in ems; the strip's width.
TOOL_EM   :: 2.1
STATUS_EM :: 1.9
STRIP_EM  :: 10.0
// Logical pixels past the machined halo's reach before the title bar's rule.
HALO_ROOM_PX :: 2
// How far a thumbnail is dragged before it moves, in logical pixels.
DRAG_START_PX :: 6

view_build :: proc(h: ^host.Host, size: host.Vec2) {
	app := (^App)(h.user)
	app.frame += 1
	clear(&app.frame_asks)
	em := ui.font_size()
	// (the user's themes file: a task looks at it now and then; app_params shows what it read)
	if prefs_page.themes_file_poll(&app.themes_file, &h.state) { host.host_settle(h) }
	// (the dialogs and the views: the palette, the keys' sheet, the confirmations, around and over the page)
	if ui.views_frame(&app.views) {
		window_keys(app)
		switch {
		case app.settings_open: settings_keys(app)
		case app.text.open:     text_keys(app)
		case:
			if app.text_mode && ui.key_press(.Escape) { app.text_mode = false }
			actions_keys(app)
		}
		actions_build(app)
		ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
		page := ui.build_box({.Draw_Background}, "###page")
		if ui.parent(page) { build_page(app, em, size) }
		menus_build(app, em)
		// (the install's dialog and the settings' Installation page; headless, nothing is read or offered)
		install_follow(app)
	}
	send_asks(app)
}

@(private = "file")
build_page :: proc(app: ^App, em: f32, window: host.Vec2) {
	build_title(app, em)
	ui.hline(ui.fill())
	if app.snapshot != nil && !app.settings_open && app.pending != .Locked {
		build_tools(app, em)
		ui.hline(ui.fill())
	}
	crash_bar.bar(&app.crash_bar, {name = APP_TITLE, version = APP_VERSION, repository = "sachahjkl/feuille"})
	ui.next({width = ui.fill(), height = ui.fill()})
	if ui.row() {
		switch {
		case app.settings_open:
			ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
			if ui.column() { settings_build(app) }
		case app.pending == .Locked:
			password_view(app, em)
		case app.snapshot == nil:
			ui.next({width = ui.fill(), height = ui.fill()})
			if ui.column() { empty_view(app) }
		case:
			if app.thumbs_shown {
				strip_view(app, em, window)
				vline()
			}
			pages_view(app, window)
		}
	}
	ui.hline(ui.fill())
	build_status(app, em)
}

// A vertical rule between the strip and the pages, as hline draws the horizontal ones.
@(private = "file")
vline :: proc() {
	line := max(1, math.round(ui.scale()))
	ui.next({width = ui.px(ui.machined() ? 2 * line : line), height = ui.fill(), bg = ui.color("border")})
	ui.build_box({.Draw_Background, .Groove}, "")
}

// An icon of Lucide, `width` wide.
@(private = "file")
glyph :: proc(g: string, width: f32, fg: Maybe(ui.Color) = nil, size: f32 = 0) {
	ui.next({width = ui.px(width), height = ui.pct(1), font = ui.lucide_icons(), font_size = size > 0 ? size : ui.font_size(), text_align = .Center, fg = fg})
	ui.build_box({.Draw_Text, .No_Text_Trunc}, fmt.tprintf("%s###g%d", g, ui.parent_box().child_count))
}

// A tool for an action of the table: its glyph, its label and keys as its tip, its act name (the palette's Shift+Enter
// on the action comes to it), lit while a switch is on.
@(private = "file")
tool :: proc(app: ^App, a: Action, em: f32) {
	c := ACTIONS[a]
	ui.next({width = ui.px(em * TOOL_EM), height = ui.px(em * TOOL_EM), radius = em * 0.4})
	sig := ui.button(c.id, icon = c.icon, o = {tip = ui.command_tip(c), icon_font = ui.lucide_icons(), disabled = !action_enabled(app, a), lit = action_on(app, a)})
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
		case app.snapshot != nil:
			title = filepath.base(app.snapshot.path)
			if app.snapshot.edited { title = fmt.tprintf("%s · %s", title, i18n.tr("edited")) }
		}
		ui.next({width = ui.fill(), height = ui.pct(1)})
		ui.label(fmt.tprintf("%s###title", title))
		if app.settings_open {
			ui.next({width = ui.px(em * TOOL_EM), height = ui.px(em * TOOL_EM), radius = em * 0.4})
			if ui.button("back", icon = lucide.ARROW_LEFT, o = {tip = ui.key_tip(i18n.tr("Back to the document"), {.Escape, {}}), icon_font = ui.lucide_icons()}).clicked { app.settings_open = false }
		} else {
			tool(app, .Open, em)
			if app.snapshot != nil { tool(app, .Save, em) }
			tool(app, .Settings, em)
		}
		// (the window's own buttons at its edge: minimise, maximise or restore, close, which asks as Quit does; the system's
		// title bar has its own, and window_buttons draws nothing then)
		if app.settings.system_title {
			ui.space(ui.SPACE_2)
		} else {
			ui.space(ui.TOOL_GAP)
			ui.window_buttons()
		}
	}
}

// The document's tools, in groups: the history, the page, the text, the view.
@(private = "file")
build_tools :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * (TOOL_EM + 0.5)))})
	ui.a11y({role = .Toolbar, name = i18n.tr("Document tools")})
	if ui.row(.Center) {
		ui.space(ui.SPACE_2)
		tool(app, .Thumbnails, em)
		ui.space(ui.CONTROL_GAP)
		tool(app, .Undo, em)
		tool(app, .Redo, em)
		ui.space(ui.CONTROL_GAP)
		tool(app, .Rotate_Left, em)
		tool(app, .Rotate_Right, em)
		tool(app, .Move_Up, em)
		tool(app, .Move_Down, em)
		tool(app, .Insert_Blank, em)
		tool(app, .Insert_File, em)
		tool(app, .Remove_Page, em)
		tool(app, .Extract_Page, em)
		ui.space(ui.CONTROL_GAP)
		tool(app, .Edit_Text, em)
		if app.text_mode { stamp_style_bar(app, em) }
		tool(app, .Layer, em)
		ui.spacer(ui.fill())
		tool(app, .Zoom_Out, em)
		ui.next({width = ui.text_size(em * 0.4), height = ui.pct(1), text_align = .Center})
		if ui.tags("weak") { ui.label(fmt.tprintf("%d %%###zoom", int(math.round(ui.zoom_zone_value(&app.zone) * 100)))) }
		tool(app, .Zoom_In, em)
		tool(app, .Fit, em)
		ui.space(ui.SPACE_2)
	}
}

@(private = "file")
build_status :: proc(app: ^App, em: f32) {
	ui.next({width = ui.fill(), height = ui.px(ui.dense(em * STATUS_EM))})
	ui.a11y({role = .Status, live = .Polite})
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
						if at := selected_index(app); at >= 0 && at != app.current { msg = fmt.tprintf(i18n.tr("%s · page %d selected"), msg, at + 1) }
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

failure_text :: proc(e: Open_Error) -> string {
	switch e {
	case .None:        return ""
	case .File:        return i18n.tr("The file cannot be read.")
	case .Format:      return i18n.tr("It is not a PDF, or it is damaged.")
	case .Security:    return i18n.tr("Its protection is of a kind this program does not know.")
	case .Password:    return i18n.tr("The password is wrong.")
	case .Unavailable: return i18n.tr("This build of the program has no PDF engine.")
	case .Failed:      return i18n.tr("The PDF engine refused it.")
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

// The text tool's style, while it is on: the family, bold and italic, the size, the colour of the words and of their
// background (src/md/features/stamps.md). It applies to the stamp being written and to the next ones.
@(private = "file")
stamp_style_bar :: proc(app: ^App, em: f32) {
	s := &app.style
	ui.space(ui.CONTROL_GAP)
	family := int(s.font.family)
	ui.next({height = ui.px(em * TOOL_EM)})
	if ui.segmented("###stamp_family", {i18n.tr("Sans"), i18n.tr("Serif"), i18n.tr("Mono")}, &family) { s.font.family = pdf.Family(family) }
	ui.space(ui.ICON_GAP)
	style_toggle :: proc(id, glyph, tip: string, on: ^bool, em: f32) {
		ui.next({width = ui.px(em * TOOL_EM), height = ui.px(em * TOOL_EM), radius = em * 0.4})
		if ui.button(id, icon = glyph, o = {tip = tip, icon_font = ui.lucide_icons(), lit = on^}).clicked { on^ = !on^ }
	}
	style_toggle("stamp_bold", lucide.BOLD, i18n.tr("Bold"), &s.font.bold, em)
	style_toggle("stamp_italic", lucide.ITALIC, i18n.tr("Italic"), &s.font.italic, em)
	ui.space(ui.ICON_GAP)
	size := int(s.size)
	ui.next({width = ui.px(em * 7.5), height = ui.px(em * TOOL_EM)})
	if ui.number("###stamp_size", &size, 4, 144, unit = "pt") { s.size = f32(size) }
	ui.space(ui.CONTROL_GAP)
	for c, i in STAMP_INKS { swatch(fmt.tprintf("###ink%d", i), {c[0], c[1], c[2], 255}, s.color == c, false, em, i18n.tr("Text colour"), &s.color, c, nil) }
	ui.space(ui.ICON_GAP)
	for c, i in STAMP_GROUNDS { swatch(fmt.tprintf("###ground%d", i), c, s.background == c, true, em, i18n.tr("Background"), nil, {}, &s.background) }
}

// The colours of a stamp's words, and of its background (alpha 0: none).
@(private = "file", rodata) STAMP_INKS := [?][3]u8{{0, 0, 0}, {29, 78, 216}, {185, 28, 28}, {255, 255, 255}}
@(private = "file", rodata) STAMP_GROUNDS := [?][4]u8{{0, 0, 0, 0}, {255, 255, 255, 255}, {253, 230, 138, 255}, {0, 0, 0, 255}}

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
	if d.none {
		draw.rect(dc, inner, draw.WHITE, radius = 2 * d.scale)
		draw.line(dc, {inner.min.x, inner.max.y}, {inner.max.x, inner.min.y}, 1.5 * d.scale, {0.8, 0.1, 0.1, 1})
	} else {
		draw.rect(dc, inner, d.color, radius = 2 * d.scale)
	}
	draw.rect(dc, inner, d.edge, radius = 2 * d.scale, border = d.scale)
	if d.chosen { draw.rect(dc, r, d.accent, radius = 3 * d.scale, border = 2 * d.scale) }
}

// A colour to choose: a square of it, ringed when chosen; a click sets `ink` (the words' colour) or `ground`.
@(private = "file")
swatch :: proc(id: string, c: [4]u8, chosen, ground: bool, em: f32, tip: string, ink: ^[3]u8, ink_value: [3]u8, ground_ptr: ^[4]u8) {
	d := ui.frame_new(Swatch_Draw)
	d.color = {f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, 1}
	d.chosen, d.none, d.scale = chosen, ground && c[3] == 0, ui.scale()
	d.accent, d.edge = ui.color("accent"), ui.color("border")
	ui.next({width = ui.px(em * 1.6), height = ui.px(em * 1.6)})
	b := ui.custom(id, swatch_draw, d, {.Clickable})
	if ui.a11y_wanted() { ui.a11y_set(b, {role = .Button, name = tip, selected = chosen}) }
	if ui.signal(b).clicked {
		if ink != nil { ink^ = ink_value }
		if ground_ptr != nil { ground_ptr^ = c }
	}
}

// What a page's box draws: its sheet and a soft shadow, its picture when it has one, a ring when it is selected, and
// with the text tool on, the outline of each stamp.
@(private = "file")
Page_Draw :: struct {
	tex:      render.Texture,
	has:      bool,
	shadow:   draw.Color,
	accent:   draw.Color,
	selected: bool,
	scale:    f32,
	stamps:   [][4]f32,   // shares of the page (frame memory)
}

@(private = "file")
page_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Page_Draw)(user)
	lift := 2 * d.scale
	draw.rect(dc, {b.rect.min + {0, lift}, b.rect.max + {0, lift}}, d.shadow, soft = 6 * d.scale)
	draw.rect(dc, b.rect, draw.WHITE)   // (a page's paper is white whatever the theme: the engine draws on white)
	if d.has { draw.image(dc, d.tex, b.rect) }
	if d.selected {
		ring := 2 * d.scale
		draw.rect(dc, {b.rect.min - ring, b.rect.max + ring}, d.accent, radius = ring, border = ring)
	}
	size := b.rect.max - b.rect.min
	for s in d.stamps {
		r := draw.Rect{b.rect.min + {s[0], s[1]} * size, b.rect.min + {s[2], s[3]} * size}
		draw.rect(dc, {r.min - 2 * d.scale, r.max + 2 * d.scale}, d.accent, border = d.scale)
	}
}

// The view's size, as the last layout of `box` found it (`fallback` before the first), less the vertical scroll bar's
// room: a column fitted to the whole box would overflow it by the bar and scroll sideways.
@(private = "file")
view_of :: proc(box: ^ui.Box, fallback: host.Vec2) -> [2]f32 {
	view := [2]f32{box.rect.max.x - box.rect.min.x, box.rect.max.y - box.rect.min.y}
	if view.x <= 0 || view.y <= 0 { view = fallback }
	view.x = max(view.x - SCROLL_BAR_ROOM, 1)
	return view
}

@(private = "file")
pages_view :: proc(app: ^App, window: host.Vec2) {
	zoom := ui.zoom_zone(&app.zone, app.snapshot.path)
	ui.next({width = ui.fill(), height = ui.fill(), axis = .Y})
	box := ui.build_box({.Clip, .View_Scroll_X, .View_Scroll_Y, .View_Clamp_X, .View_Clamp_Y, .Allow_Overflow_X, .Allow_Overflow_Y}, "###pages")
	if ui.a11y_wanted() { ui.a11y_set(box, {role = .Document, name = filepath.base(app.snapshot.path)}) }
	_ = ui.signal(box)
	if ui.parent(box) { pages_column(app, box, zoom, window) }
}

@(private = "file")
pages_column :: proc(app: ^App, box: ^ui.Box, zoom: f32, window: host.Vec2) {
	s := app.snapshot
	view := view_of(box, window)
	if app.to_top {
		box.view_off, box.view_target = {}, {}
		app.to_top = false
	}
	if layout_stale(app.layout, s.revision, view.x, zoom) {
		// (the point at the middle of the view stays there through a zoom, a resize or an edit)
		page, fraction := layout_at(app.layout, box.view_off.y + view.y / 2)
		keep := page >= 0 && page < len(app.layout.tops)
		layout_make(&app.layout, s.revision, s.pages, view.x, zoom, ui.scale())
		if keep && page < len(app.layout.tops) {
			y := max(app.layout.tops[page] + fraction * app.layout.sizes[page].y - view.y / 2, 0)
			box.view_off.y, box.view_target.y = y, y
		}
	}
	l := &app.layout
	if len(l.tops) == 0 { return }
	if app.go_to >= 0 && app.go_to < len(l.tops) {
		box.view_target.y = max(l.tops[app.go_to] - PAGE_MARGIN, 0)
		if app.go_jump { box.view_off.y = box.view_target.y }
	}
	app.go_to, app.go_jump = -1, false
	top := box.view_off.y
	app.current, _ = layout_at(l^, top + view.y / 2)
	recent_page_keep(app)
	first, last := layout_range(l^, top - view.y * VIEW_AHEAD, top + view.y * (1 + VIEW_AHEAD))
	want_pictures(app, l, first, last, top + view.y / 2, false)
	if first >= last { return }

	shadow, accent := ui.color("shadow"), ui.color("accent")
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
				d.shadow, d.accent, d.scale = shadow, accent, ui.scale()
				d.selected = p.id == app.selected && len(s.pages) > 1
				if app.text_mode && len(p.stamps) > 0 {
					d.stamps = make([][4]f32, len(p.stamps), context.temp_allocator)
					for st, k in p.stamps { d.stamps[k] = st.box }
				}
				if shown, ok := &app.pictures[p.id]; ok {
					d.tex, d.has = shown.tex, true
					shown.seen = app.frame
				}
				size := l.sizes[i]
				ui.next({width = ui.px(size.x), height = ui.px(size.y)})
				b := ui.custom(fmt.tprintf("###page%d", p.id), page_draw, d, {.Clickable})
				if app.text_mode { b.cursor = .Text }
				// (a screen reader's words for the page; made only for a build that sends the tree)
				if ui.a11y_wanted() { ui.a11y_set(b, {role = .Image, name = fmt.tprintf(i18n.tr("Page %d of %d"), i + 1, len(s.pages)), selected = p.id == app.selected}) }
				sig := ui.signal(b)
				if sig.right_clicked { page_menu_open(app, p.id, i) }
				if sig.clicked || sig.double_clicked {
					app.selected, app.selected_at = p.id, i
					at := [2]f32{sig.mouse.x / max(size.x, 1), sig.mouse.y / max(size.y, 1)}
					// (the tool places or opens a stamp; without it, a double click opens the stamp under it)
					if app.text_mode || (sig.double_clicked && stamp_at(p, at) >= 0) { stamp_click(app, p, at) }
				}
				if app.text.open && app.text.id == p.id {
					if ui.parent(b) { text_field(app, size) }
				}
				ui.spacer(ui.fill())
			}
		}
		below := l.height - (l.tops[last - 1] + l.sizes[last - 1].y)
		ui.spacer(ui.px(below), exact = true)
	}
}

// The field over the stamp being written, inside its page's box: at the stamp (or the point clicked), as wide as the
// stamp and a little more for the words that grow it, one line high at least.
@(private = "file")
text_field :: proc(app: ^App, page: [2]f32) {
	bx := app.text.box
	em := ui.font_size()
	x, y := bx[0] * page.x, bx[1] * page.y
	w := max((bx[2] - bx[0]) * page.x + em * 4, em * 12)
	h := max((bx[3] - bx[1]) * page.y, em * 1.9)
	ui.next({fixed_x = x, fixed_y = y, width = ui.px(w), height = ui.px(h)})
	res := ui.line_edit("###text_edit", &app.text.field, {placeholder = i18n.tr("Text to put on the page")})
	if app.text.focus {
		ui.set_focus(res.box.key)
		app.text.focus = false
	}
	if res.committed { text_edit_commit(app) }
}

// Escape gives the words up; a click elsewhere commits them (text_pick, a page's click).
@(private = "file")
text_keys :: proc(app: ^App) {
	if ui.key_press(.Escape) { text_edit_close(app) }
}

// What a thumbnail draws: its picture, a ring when selected, a line where a dragged page would go.
@(private = "file")
Thumb_Draw :: struct {
	tex:      render.Texture,
	has:      bool,
	selected: bool,
	current:  bool,
	dragged:  bool,
	accent:   draw.Color,
	edge:     draw.Color,
	scale:    f32,
}

@(private = "file")
thumb_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Thumb_Draw)(user)
	draw.rect(dc, b.rect, draw.WHITE)
	if d.has { draw.image(dc, d.tex, b.rect, tint = d.dragged ? {1, 1, 1, 0.4} : draw.WHITE) }
	ring := 2 * d.scale
	switch {
	case d.selected: draw.rect(dc, {b.rect.min - ring, b.rect.max + ring}, d.accent, radius = ring, border = ring)
	case d.current:  draw.rect(dc, {b.rect.min - ring / 2, b.rect.max + ring / 2}, d.edge, border = ring / 2)
	}
}

// The strip of thumbnails: every page small, the selected one ringed; a click selects and shows it, a drag moves it.
@(private = "file")
strip_view :: proc(app: ^App, em: f32, window: host.Vec2) {
	ui.next({width = ui.px(em * STRIP_EM), height = ui.fill(), axis = .Y})
	box := ui.build_box({.Clip, .View_Scroll_Y, .View_Clamp_Y, .Allow_Overflow_Y}, "###strip")
	if ui.a11y_wanted() { ui.a11y_set(box, {role = .List, name = i18n.tr("Thumbnails")}) }
	_ = ui.signal(box)
	if ui.parent(box) { strip_column(app, box, em, window) }
}

@(private = "file")
strip_column :: proc(app: ^App, box: ^ui.Box, em: f32, window: host.Vec2) {
	s := app.snapshot
	view := view_of(box, {em * STRIP_EM, window.y})
	l := &app.thumb_layout
	if layout_stale(l^, s.revision, view.x, 1) { layout_make(l, s.revision, s.pages, view.x, 1, ui.scale()) }
	if len(l.tops) == 0 { return }
	top := box.view_off.y
	first, last := layout_range(l^, top - view.y, top + view.y * 2)
	want_pictures(app, l, first, last, top + view.y / 2, true)
	if first >= last { return }

	// the drag: where the page held would go, from the pointer's height in the strip
	if app.drag_id != 0 {
		y := ui.mouse_pos().y - box.rect.min.y + top
		page, fraction := layout_at(l^, y)
		app.drop_at = page + (fraction > 0.5 ? 1 : 0)
	}
	accent, edge := ui.color("accent"), ui.color("border")
	ui.next({width = ui.px(view.x), height = ui.children_sum()})
	if ui.column(.Center) {
		ui.spacer(ui.px(l.tops[first]), exact = true)
		for i in first ..< last {
			if i > first { ui.spacer(ui.px(PAGE_GAP), exact = true) }
			p := s.pages[i]
			if app.drag_id != 0 && app.drop_at == i { drop_line(app, view.x, accent) }
			d := ui.frame_new(Thumb_Draw)
			d.selected, d.current, d.dragged = p.id == app.selected, i == app.current, p.id == app.drag_id
			d.accent, d.edge, d.scale = accent, edge, ui.scale()
			if shown, ok := &app.thumbs[p.id]; ok {
				d.tex, d.has = shown.tex, true
				shown.seen = app.frame
			}
			ui.next({width = ui.px(l.sizes[i].x), height = ui.px(l.sizes[i].y)})
			tb := ui.custom(fmt.tprintf("###thumb%d", p.id), thumb_draw, d, {.Clickable})
			if ui.a11y_wanted() { ui.a11y_set(tb, {role = .List_Item, name = fmt.tprintf(i18n.tr("Page %d of %d"), i + 1, len(s.pages)), selected = p.id == app.selected, position = i + 1, set_size = len(s.pages)}) }
			sig := ui.signal(tb)
			if sig.right_clicked { page_menu_open(app, p.id, i) }
			if sig.dragging && app.drag_id == 0 && abs(sig.drag_delta.y) > DRAG_START_PX * ui.scale() {
				app.drag_id, app.drop_at = p.id, i
			}
			if sig.released && app.drag_id == p.id { thumb_dropped(app, i) }
			if sig.clicked && app.drag_id == 0 { go_to_page(app, i) }
		}
		if app.drag_id != 0 && app.drop_at >= last { drop_line(app, view.x, accent) }
		below := l.height - (l.tops[last - 1] + l.sizes[last - 1].y)
		ui.spacer(ui.px(below), exact = true)
	}
	// (the button let go anywhere else: the drag ends where it is)
	if app.drag_id != 0 && ui.active_key() == 0 { app.drag_id = 0 }
}

// The accent line where a dragged thumbnail would go.
@(private = "file")
drop_line :: proc(app: ^App, width: f32, accent: draw.Color) {
	ui.next({width = ui.px(width * 0.8), height = ui.px(3), bg = accent, radius = 1.5})
	ui.build_box({.Draw_Background}, "###drop")
}

// A thumbnail let go: its page moves to where the line is (one undoable edit).
@(private = "file")
thumb_dropped :: proc(app: ^App, from: int) {
	id := app.drag_id
	app.drag_id = 0
	to := app.drop_at
	// (the line is between two pages: below its own place, the page takes the slot before it)
	if to > from { to -= 1 }
	if to == from { return }
	app.selected, app.selected_at = id, to
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Move, id = id, to = to))
}

// The pictures of [first, last) of layout `l` that are missing or stale, the nearest to `middle` first, added to the
// frame's list (send_asks sends it).
@(private = "file")
want_pictures :: proc(app: ^App, l: ^Layout, first, last: int, middle: f32, thumb: bool) {
	s := app.snapshot
	k := ui.scale()
	cache := thumb ? &app.thumbs : &app.pictures
	start := len(app.frame_asks)
	for i in first ..< last {
		p := s.pages[i]
		size := [2]int{int(math.round(l.sizes[i].x * k)), int(math.round(l.sizes[i].y * k))}
		if size.x <= 0 || size.y <= 0 { continue }
		// (a thumbnail draws the page's own content: the strip is for finding a page, the layer is the page's)
		layer := thumb ? false : app.layer
		if shown, ok := cache[p.id]; ok && shown.size == size && shown.layer == layer && shown.version == p.version { continue }
		append(&app.frame_asks, Render_Ask{revision = s.revision, index = i, id = p.id, version = p.version, size = size, layer = layer, thumb = thumb})
	}
	// nearest first (a handful of pages: an insertion sort)
	asks := app.frame_asks[start:]
	distance :: proc(l: ^Layout, i: int, middle: f32) -> f32 { return abs(l.tops[i] + l.sizes[i].y / 2 - middle) }
	for i in 1 ..< len(asks) {
		for j := i; j > 0 && distance(l, asks[j].index, middle) < distance(l, asks[j - 1].index, middle); j -= 1 {
			asks[j], asks[j - 1] = asks[j - 1], asks[j]
		}
	}
}

// The frame's list to the worker, unless it is the one asked last.
@(private = "file")
send_asks :: proc(app: ^App) {
	asks := app.frame_asks[:]
	if len(asks) == 0 || same_asks(asks, app.last_ask[:]) { return }
	clear(&app.last_ask)
	append(&app.last_ask, ..asks)
	worker_render(&app.worker, asks)
}

@(private = "file")
same_asks :: proc(a, b: []Render_Ask) -> bool {
	if len(a) != len(b) { return false }
	for x, i in a { if x != b[i] { return false } }
	return true
}
