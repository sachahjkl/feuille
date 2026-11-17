package feuille

// Every act of the program, named once: its label, group, keys and icon (gui_toolkit's commands). The same table gives
// the keys, the tooltips, the command palette (Ctrl+K) and the sheet of the keys (F1).

import "core:slice"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"
import update "gt:update"

Action :: enum u8 {
	Open,
	Layer,
	Zoom_In,
	Zoom_Out,
	Fit,
	First_Page,
	Last_Page,
	Settings,
	Check_Updates,
	Shortcuts,
	Restart,
	Quit,
}

ACTIONS := [Action]ui.Command{
	.Open          = {id = "open", label = i18n.later("Open a PDF…"), group = i18n.later("Document"), keys = {{.O, {.Ctrl}}}, icon = lucide.FOLDER_OPEN, tags = {"file", "load"}, scope = .Window},
	.Layer         = {id = "layer", label = i18n.later("Show the form layer"), group = i18n.later("Document"), keys = {{.L, {.Ctrl}}}, icon = lucide.LAYERS_2, tags = {"signatures", "annotations", "fields", "form"}, toggle = true},
	.Zoom_In       = {id = "zoom_in", label = i18n.later("Zoom in"), group = i18n.later("View"), icon = lucide.ZOOM_IN, tags = {"bigger", "magnify"}},
	.Zoom_Out      = {id = "zoom_out", label = i18n.later("Zoom out"), group = i18n.later("View"), icon = lucide.ZOOM_OUT, tags = {"smaller"}},
	.Fit           = {id = "fit", label = i18n.later("Fit the width"), group = i18n.later("View"), icon = lucide.MOVE_HORIZONTAL, tags = {"zoom", "reset", "width"}},
	.First_Page    = {id = "first_page", label = i18n.later("First page"), group = i18n.later("View"), keys = {{.Home, {.Ctrl}}}, icon = lucide.ARROW_UP, tags = {"top", "start"}},
	.Last_Page     = {id = "last_page", label = i18n.later("Last page"), group = i18n.later("View"), keys = {{.End, {.Ctrl}}}, icon = lucide.ARROW_DOWN, tags = {"bottom", "end"}},
	.Settings      = {id = "settings", label = i18n.later("Settings"), group = i18n.later("Feuille"), keys = {{.Comma, {.Ctrl}}}, icon = lucide.SETTINGS, tags = {"preferences", "options", "configure"}, scope = .Window},
	.Check_Updates = {id = "check_updates", label = i18n.later("Check for updates"), group = i18n.later("Feuille"), icon = lucide.REFRESH_CW, tags = {"upgrade", "version", "new"}},
	.Shortcuts     = {id = "shortcuts", label = i18n.later("Keyboard shortcuts"), group = i18n.later("Feuille"), keys = {{.F1, {}}}, icon = lucide.KEYBOARD, tags = {"help", "keys", "hotkeys"}, scope = .Window},
	.Restart       = {id = "restart", label = i18n.later("Restart Feuille"), group = i18n.later("Feuille"), icon = lucide.ROTATE_CCW, tags = {"reload", "relaunch"}},
	.Quit          = {id = "quit", label = i18n.later("Quit Feuille"), group = i18n.later("Feuille"), keys = {{.Q, {.Ctrl}}}, icon = lucide.POWER, tags = {"exit", "close", "stop"}, scope = .Window},
}

// Whether the act can be done now.
action_enabled :: proc(app: ^App, a: Action) -> bool {
	switch a {
	case .Layer, .Zoom_In, .Zoom_Out, .Fit, .First_Page, .Last_Page:
		return app.snapshot != nil && !app.settings_open
	case .Open, .Settings, .Check_Updates, .Shortcuts, .Restart, .Quit:
		return true
	}
	return false
}

action_run :: proc(app: ^App, a: Action) {
	if !action_enabled(app, a) { return }
	switch a {
	case .Open:
		app.settings_open = false
		ui.file_dialog(&app.main.state, .Open, {owner = app.main.win, title = i18n.tr("Open a PDF"), filters = PDF_FILTERS[:], all_files = true}, open_chosen, app)
	case .Layer:         app.layer = !app.layer
	case .Zoom_In:       ui.zoom_zone_by(&app.zone, ui.feel(&app.main.state).zoom_step)
	case .Zoom_Out:      ui.zoom_zone_by(&app.zone, 1 / ui.feel(&app.main.state).zoom_step)
	case .Fit:           ui.zoom_zone_reset(&app.zone)
	case .First_Page:    app.go_to = 0
	case .Last_Page:     app.go_to = len(app.snapshot.pages) - 1
	case .Settings:      settings_toggle(app)
	case .Check_Updates: if app.updates.updater != nil { update.check_now(app.updates.updater) }
	// (the sheet adds the toolkit's palette command itself)
	case .Shortcuts:     ui.shortcuts_sheet_open(&app.sheet, slice.enumerated_array(&ACTIONS), i18n.tr("Feuille's keys"))
	case .Restart:       app_restart(app)
	case .Quit:          app.quit = true
	}
}

// The keys of the window's actions (scope .Window): in every page, before anything else reads a key. The palette's
// first: its keys are the toolkit's, read by its own reader.
window_keys :: proc(app: ^App) {
	if palette_keys(app) { return }
	for a in Action {
		if ACTIONS[a].scope != .Window { continue }
		if ui.command_pressed(ACTIONS[a], !action_enabled(app, a)) { action_run(app, a); return }
	}
}

// The keys of the document's actions, when nothing else has the keyboard.
actions_keys :: proc(app: ^App) {
	for a in Action {
		if ACTIONS[a].scope == .Window { continue }
		if ui.command_pressed(ACTIONS[a], !action_enabled(app, a)) { action_run(app, a); return }
	}
}

// (package arrays: the dialog reads them on another thread, after the build that asked)
@(rodata) PDF_PATTERNS := [?]string{"*.pdf"}
PDF_FILTERS := [?]platform.File_Filter{{name = "PDF", patterns = PDF_PATTERNS[:]}}

@(private = "file")
open_chosen :: proc(r: platform.Dialog_Result, user: rawptr) {
	if r.status != .Chosen || len(r.paths) == 0 { return }
	app_open_file((^App)(user), r.paths[0], "")
}

// The palette is the toolkit's: its commands source lists the actions, prefs_page's settings source the settings (`:`).
Palette_State :: struct {
	disabled: [Action]bool,   // the actions that cannot act, as the commands source last took them
	version:  u64,
	made_for: [2]bool,        // what `disabled` was read for: a document open, the settings open
	made:     bool,
	settings: prefs_page.Palette_Settings,
}

palette_init :: proc(app: ^App) {
	if !app.headless { ui.palette_memory_open(&app.palette, &app.main.state, palette_choices_path()) }
	open :: proc(user: rawptr) { (^App)(user).settings_open = true }
	options :: proc(user: rawptr) -> prefs_page.Page_Options { return settings_options((^App)(user)) }
	prefs_page.palette_settings_add(&app.palette, &app.palette_state.settings, &app.prefs, &app.settings_page, options, open, app)
}

// The actions and what can act now, read again only when what it depends on moved.
@(private = "file")
palette_give :: proc(app: ^App) {
	ps := &app.palette_state
	key := [2]bool{app.snapshot != nil, app.settings_open}
	if !ps.made || key != ps.made_for {
		for a in Action { ps.disabled[a] = !action_enabled(app, a) }
		ps.made_for, ps.made = key, true
		ps.version += 1
	}
	ui.palette_commands(&app.palette, slice.enumerated_array(&ACTIONS), slice.enumerated_array(&ps.disabled), {version = ps.version})
}

// Ctrl+K and Ctrl+Shift+P: the palette opens or closes. True when they were pressed.
palette_keys :: proc(app: ^App) -> bool {
	if !ui.palette_keys(&app.palette) { return false }
	palette_give(app)
	return true
}

// The palette's choice, and what can act kept while it is open: at each build.
actions_build :: proc(app: ^App) {
	if c, ok := ui.palette_chosen(&app.palette); ok {
		if i, is := ui.palette_chosen_command(&app.palette, c); is && i >= 0 && i < len(Action) { action_run(app, Action(i)) }
	}
	if ui.palette_is_open(&app.palette) { palette_give(app) }
}
