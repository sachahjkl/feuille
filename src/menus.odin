package feuille

// The context menus: a right click on a page or on a thumbnail selects that page and opens its menu. Its items are the
// actions of actions.odin (their labels, keys and icons), the page's edits and the document's file:
//
//   Turn the page right / left     Ctrl+R, Ctrl+Shift+R
//   Move the page up / down        Alt+Up, Alt+Down
//   Add a blank page after         Ctrl+Shift+N
//   Remove the page                Delete
//   Save this page as a PDF…       Ctrl+E
//   Copy the path                  Ctrl+Shift+C
//   Show in folder
//   Open with  ▸                   the applications the system knows for a PDF (gt:desktop), read on a task
//
// "Open with another application…" (the command) opens the applications' list alone, at the pointer.

import "core:fmt"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:ui"

PAGE_MENU      :: "feuille_page_menu"
OPEN_WITH_MENU :: "feuille_open_with_menu"

// The menus' least width, in ems.
MENU_WIDTH_EM :: 16

// A right press on the page `id`, at `index`: it is selected, its menu opens at the pointer.
page_menu_open :: proc(app: ^App, id: u64, index: int) {
	app.selected, app.selected_at = id, index
	if app.snapshot != nil { handlers_ask(app, app.snapshot.path) }
	ui.menu_open(PAGE_MENU, ui.mouse_pos())
}

// The menus, when one is open: at the end of the window's build.
menus_build :: proc(app: ^App, em: f32) {
	if app.snapshot == nil { return }
	if ui.menu(PAGE_MENU, em * MENU_WIDTH_EM) {
		item(app, .Rotate_Right)
		item(app, .Rotate_Left)
		item(app, .Move_Up)
		item(app, .Move_Down)
		ui.menu_separator()
		item(app, .Insert_Blank)
		item(app, .Remove_Page)
		item(app, .Extract_Page)
		ui.menu_separator()
		item(app, .Copy_Path)
		item(app, .Reveal)
		if ui.menu_submenu(i18n.tr("Open with"), icon = ACTIONS[.Open_With].icon) { open_with_items(app) }
	}
	if ui.menu(OPEN_WITH_MENU, em * MENU_WIDTH_EM) { open_with_items(app) }
}

// A line of a menu: an action, its keys and its icon from the table, greyed when it cannot act.
@(private = "file")
item :: proc(app: ^App, a: Action) {
	c := ACTIONS[a]
	sig := ui.menu_item(i18n.tr(c.label), ui.command_shortcut(c), disabled = !action_enabled(app, a), icon = c.icon)
	ui.act_command(sig.box, c.id)   // (a menu filtered by its letters builds no row: act_command takes nil)
	if sig.clicked { action_run(app, a) }
}

// The applications for the document, its default first; a row while they are read, one when there is none.
@(private = "file")
open_with_items :: proc(app: ^App) {
	h := &app.handlers
	path := app.snapshot.path
	ready := h.path == path && h.ready
	if !ready { _ = ui.menu_item(i18n.tr("Reading…"), disabled = true); return }
	if len(h.list) == 0 { _ = ui.menu_item(i18n.tr("No application"), disabled = true); return }
	for x, i in h.list {
		name := ui.text_shown(x.name)
		label := x.default ? fmt.tprintf("%s###ow%d", fmt.tprintf(i18n.tr("%s (default)"), name), i) : fmt.tprintf("%s###ow%d", name, i)
		if ui.menu_item(label, icon = lucide.APP_WINDOW).clicked { launch(app, .Open_With, path, x.id, x.name) }
	}
}
