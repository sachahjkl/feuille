package feuille

// What the program's own commands do (actions.odin, the "Feuille" and "Window" groups of the palette): the window, the
// updates, about feuille, the look's settings a key away. The same commands as the suite's other programs, by the same
// ids and keys (classeur's program_actions.odin).

import "base:runtime"
import "core:fmt"
import config "gt:config"
import i18n "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import update "gt:update"
import "gt:ui"

SITE_URL       :: "https://feuille.froment.software/"
REPOSITORY_URL :: "https://github.com/sachahjkl/feuille"

////////////////////////////////
// The window

// Another feuille, with no file, of its own (a second start would hand its file to this one: none is given, and the
// new process owns nothing). Started on a task: a start may wait.
act_new_window :: proc(app: ^App) { launch(app, .New_Window, app.exe) }

act_minimize :: proc(app: ^App) { platform.minimize(app.main.win) }
act_maximize :: proc(app: ^App) { platform.toggle_maximize(app.main.win) }
act_full_screen :: proc(app: ^App) { platform.set_fullscreen(app.main.win, !platform.is_fullscreen(app.main.win)) }

////////////////////////////////
// Updates (updates.odin)

act_update_check :: proc(app: ^App) { if app.updates.updater != nil { update.check_now(app.updates.updater) } }
act_update_install :: proc(app: ^App) { if app.updates.updater != nil { update.install_now(app.updates.updater) } }

has_updater :: proc(app: ^App) -> bool { return app.updates.updater != nil }
update_available :: proc(app: ^App) -> bool { return app.updates.updater != nil && update.status(app.updates.updater).phase == .Available }
update_installed :: proc(app: ^App) -> bool { return app.updates.updater != nil && update.status(app.updates.updater).phase == .Installed }

////////////////////////////////
// About feuille

act_about :: proc(app: ^App) {
	say(app, i18n.tr("Feuille %s, on gui_toolkit %s. %s"), APP_VERSION, ui.VERSION, SITE_URL)
}

act_website :: proc(app: ^App) { launch(app, .Url, SITE_URL) }
act_report :: proc(app: ^App) { launch(app, .Url, REPOSITORY_URL + "/issues") }
act_changelog :: proc(app: ^App) { launch(app, .Url, REPOSITORY_URL + "/releases") }

// Where the settings are (prefs_file's folder).
act_settings_folder :: proc(app: ^App) {
	launch(app, .Folder, platform.user_dir(.Config, APP_FOLDER, context.temp_allocator))
}

act_version_copy :: proc(app: ^App) {
	platform.set_clipboard(app.main.win, APP_TITLE + " " + APP_VERSION)
	ui.announce(&app.announcer, .Good, i18n.tr("The version is copied"))
}

////////////////////////////////
// The look: the settings' values, a key away

act_theme_next :: proc(app: ^App) { theme_step(app, 1) }
act_theme_previous :: proc(app: ^App) { theme_step(app, -1) }

// The theme after or before this one, in the settings' order (their cards').
@(private = "file")
theme_step :: proc(app: ^App, by: int) {
	list := app.themes_file.all[:]
	n := len(list)
	if n == 0 { return }
	at := 0
	for t, i in list { if t.name == app.settings.look.theme { at = i } }
	name := list[((at + by) % n + n) % n].name
	pref_set_string(app, prefs_page.THEME_PREF, name)
	say(app, i18n.tr("Theme: %s"), name)
}

// The density of the compact rows, the suite's value: the toolkit's controls, a little closer.
DENSITY_COMPACT :: 0.82

act_density :: proc(app: ^App) {
	compact := config.float_of(&app.prefs, "appearance.density") < 1
	if compact {
		_ = config.reset(&app.prefs, "appearance.density")
		settings_reread(app)
	} else {
		pref_set_string(app, "appearance.density", fmt.tprintf("%v", DENSITY_COMPACT))
	}
	say(app, compact ? i18n.tr("Comfortable rows") : i18n.tr("Compact rows"))
}

// Never, or always: "system" (the default) leaves it to the system, which a key cannot tell, so it goes to never first.
act_animations :: proc(app: ^App) {
	off := config.string_of(&app.prefs, "appearance.animations") == "off"
	pref_set_string(app, "appearance.animations", off ? "on" : "off")
	say(app, off ? i18n.tr("Animations on") : i18n.tr("Animations off"))
}

// The text's size by a point, within the setting's bounds.
TEXT_STEP :: 1

act_text_bigger :: proc(app: ^App) { text_size_step(app, TEXT_STEP) }
act_text_smaller :: proc(app: ^App) { text_size_step(app, -TEXT_STEP) }

act_text_reset :: proc(app: ^App) {
	_ = config.reset(&app.prefs, prefs_page.FONT_SIZE_PREF)
	settings_reread(app)
	say(app, i18n.tr("Text size: %v"), app.settings.look.font_size)
}

@(private = "file")
text_size_step :: proc(app: ^App, by: f32) {
	size := clamp(app.settings.look.font_size + by, prefs_page.FONT_SIZE_MIN, prefs_page.FONT_SIZE_MAX)
	if size == app.settings.look.font_size { return }
	pref_set_string(app, prefs_page.FONT_SIZE_PREF, fmt.tprintf("%v", size))
	say(app, i18n.tr("Text size: %v"), app.settings.look.font_size)
}

// A preference set as the settings page sets it: the user's layer, which the writer saves; the standard ones are
// applied by standard_watch, feuille's read again here.
@(private = "file")
pref_set_string :: proc(app: ^App, name, text: string) {
	context.allocator = runtime.heap_allocator()
	_ = config.set_from_string(&app.prefs, name, text, .User)
	settings_reread(app)
}

////////////////////////////////
// The document's own acts: its file with the desktop

// "Open with another application…": the menu of the applications the system knows for a PDF, at the pointer.
act_open_with :: proc(app: ^App) {
	handlers_ask(app, app.snapshot.path)
	ui.menu_open(OPEN_WITH_MENU, ui.mouse_pos())
}

act_reveal :: proc(app: ^App) { launch(app, .Reveal, app.snapshot.path) }

act_copy_path :: proc(app: ^App) {
	platform.set_clipboard(app.main.win, app.snapshot.path)
	ui.announce(&app.announcer, .Good, i18n.tr("The path is copied"))
}
