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
//   Open with  ▸                   the applications the system knows for a PDF, with their icons (ui.Open_With)
//
// "Open with another application…" (the command) opens the applications' list alone, at the pointer.

import i18n "gt:i18n"
import "gt:ui"

PAGE_MENU      :: "feuille_page_menu"
OPEN_WITH_MENU :: "feuille_open_with_menu"

// The menus' least width, in ems.
MENU_WIDTH_EM :: 16

// A right press on the page `id`, at `index`: it is selected, its menu opens at the pointer.
page_menu_open :: proc(app: ^App, id: u64, index: int) {
	app.selected, app.selected_at = id, index
	ui.shell_menu_clear(&app.shell_menu)
	if app.snapshot != nil {
		open_with_ask(app, app.snapshot.path)
		if !app.headless && app.snapshot.path != "" {
			excluded := ui.SHELL_MENU_DEFAULT_EXCLUDE
			_ = ui.shell_menu_query(&app.shell_menu, &app.main.state, {paths = {app.snapshot.path}, exclude_verbs = excluded[:]})
		}
	}
	ui.menu_open(PAGE_MENU, ui.mouse_pos())
}

// The menus, when one is open: at the end of the window's build.
menus_build :: proc(app: ^App, em: f32) {
	if app.snapshot == nil { return }
	if ui.menu(PAGE_MENU, em * MENU_WIDTH_EM) {
		app.menu_was_open = true
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
		if ui.menu_submenu(i18n.tr("Open with"), icon = ACTIONS[.Open_With].icon, icon_font = ui.lucide_icons()) { open_with_items(app) }
		_ = ui.shell_menu_items(&app.shell_menu, prefix = "sh", separator = true, win = app.main.win, invoke = !app.headless)
	} else if app.menu_was_open {
		app.menu_was_open = false
		ui.shell_menu_clear(&app.shell_menu)
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

// The applications for the document, with their icons, its default first. The one chosen starts through launch: the
// tests note it, and a failure is said in the status bar as the other launches'.
@(private = "file")
open_with_items :: proc(app: ^App) {
	if !ui.open_with_items(&app.open_with, "ow") { return }
	if h, ok := ui.open_with_chosen(&app.open_with); ok { launch(app, .Open_With, app.open_with.path, h.id, h.name) }
}
