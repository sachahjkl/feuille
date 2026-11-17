package feuille

// The settings: gui_toolkit's page of the preferences (gt:prefs_page), in place of the document. The gear of the title
// bar or Ctrl+, opens it; the arrow, Escape or Ctrl+, again goes back. Each change is applied at once: the toolkit's
// standard settings by prefs_page.standard_watch, feuille's by settings_changed. The writer saves the file off the
// interface's thread.

import "base:runtime"
import i18n "gt:i18n"
import lucide "gt:lucide"
import prefs_page "gt:prefs_page"
import "gt:ui"

settings_toggle :: proc(app: ^App) {
	app.settings_open = !app.settings_open
	if app.settings_open { prefs_page.focus_search(&app.settings_page) }
}

// Escape goes back, unless an editor of a preference has the keyboard (Escape gives it back to the list first).
settings_keys :: proc(app: ^App) {
	if prefs_page.escape_leaves(&app.settings_page) { app.settings_open = false }
}

// The pages, their order and their icons: each a group of the registry (a name's first segment). The toolkit adds its
// own: the licence, the installation, What's new, the diagnostics.
@(private = "file")
SETTINGS_PAGES := [?]prefs_page.Page_Info{
	{category = "general",    title = i18n.later("General"),          icon = lucide.SETTINGS},
	{category = "view",       title = i18n.later("Document"),         icon = lucide.FILE_TEXT},
	{category = "appearance", title = i18n.later("Appearance"),       icon = lucide.PALETTE},
	{category = "window",     title = i18n.later("Window"),           icon = lucide.APP_WINDOW},
	{category = "scrolling",  title = i18n.later("Scrolling"),        icon = lucide.MOUSE},
	{category = "input",      title = i18n.later("Input"),            icon = lucide.KEYBOARD},
	{category = "timing",     title = i18n.later("Delays and menus"), icon = lucide.TIMER},
	{category = "keys",       title = i18n.later("Keys"),             icon = lucide.COMMAND},
	{category = "update",     title = i18n.later("Updates"),          icon = lucide.DOWNLOAD},
	{category = "rendering",  title = i18n.later("Rendering"),        icon = lucide.MONITOR},
}

// The page, as large as the body.
settings_build :: proc(app: ^App) {
	ui.next({width = ui.fill(), height = ui.fill()})
	prefs_page.build(&app.settings_page, &app.prefs, settings_options(app))
}

// What the page is given; the palette lists the settings by it too.
settings_options :: proc(app: ^App) -> prefs_page.Page_Options {
	return {
		user = app, changed = settings_changed,
		updater = app.updates.updater, restart = proc(user: rawptr) { app_restart((^App)(user)) },
		pages = SETTINGS_PAGES[:], icon_font = ui.lucide_icons(), search_icon = lucide.SEARCH, reset_icon = lucide.ROTATE_CCW,
		file = app.prefs_path,
		version = APP_TITLE + " " + APP_VERSION,
		themes = app.themes_file.all[:], themes_light = app.theme_shown.light, themes_file = &app.themes_file,
		changelog = &app.changelog, licence = &app.licence, install = &app.install, diagnostics = &app.main,
	}
}

// A preference was set or reset: feuille's read again (the standard ones are applied by standard_watch already); the
// menu's and the session's switches are made so on the desktop.
@(private = "file")
settings_changed :: proc(user: rawptr, name: string) {
	app := (^App)(user)
	settings_reread(app)
}

// feuille's values read again from the registry, and what follows them.
settings_reread :: proc(app: ^App) {
	context.allocator = runtime.heap_allocator()   // (the settings are the App's, whoever calls: the page, a command)
	settings_free(&app.settings)
	app.settings = prefs_read(&app.prefs)
	app.announcer.mode = announce_mode(app)
	app_title_follow(app)
}
