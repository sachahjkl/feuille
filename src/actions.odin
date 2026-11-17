package feuille

// Every act of the program, once: the keyboard, the toolbar and the palette read this table.

import "gt:lucide"
import "gt:platform"
import "gt:ui"

Action :: enum u8 {
	Open,
	Layer,
	Zoom_In,
	Zoom_Out,
	Fit,
	Quit,
}

ACTIONS := [Action]ui.Command{
	.Open     = {id = "open", label = "Open a PDF", group = "File", keys = {{.O, {.Ctrl}}}, icon = lucide.FOLDER_OPEN},
	.Layer    = {id = "layer", label = "Show the form layer", group = "View", tags = {"signatures", "annotations", "fields"}, keys = {{.L, {.Ctrl}}}, icon = lucide.LAYERS_2, toggle = true},
	.Zoom_In  = {id = "zoom_in", label = "Zoom in", group = "View", icon = lucide.ZOOM_IN},
	.Zoom_Out = {id = "zoom_out", label = "Zoom out", group = "View", icon = lucide.ZOOM_OUT},
	.Fit      = {id = "fit", label = "Fit the width", group = "View", icon = lucide.MOVE_HORIZONTAL},
	.Quit     = {id = "quit", label = "Quit", group = "File", tags = {"exit", "close"}, keys = {{.Q, {.Ctrl}}}, scope = .Window},
}

// Whether the act can be done now.
action_enabled :: proc(app: ^App, a: Action) -> bool {
	switch a {
	case .Open, .Quit: return true
	case .Layer, .Zoom_In, .Zoom_Out, .Fit: return app.snapshot != nil
	}
	return false
}

action_run :: proc(app: ^App, a: Action) {
	if !action_enabled(app, a) { return }
	switch a {
	case .Open:
		ui.file_dialog(&app.main.state, .Open, {owner = app.main.win, title = "Open a PDF", filters = PDF_FILTERS[:], all_files = true}, open_chosen, app)
	case .Layer:
		app.layer = !app.layer
	case .Zoom_In:
		ui.zoom_zone_by(&app.zone, ui.feel(&app.main.state).zoom_step)
	case .Zoom_Out:
		ui.zoom_zone_by(&app.zone, 1 / ui.feel(&app.main.state).zoom_step)
	case .Fit:
		ui.zoom_zone_reset(&app.zone)
	case .Quit:
		platform.request_close(app.main.win)
	}
}

// The keys of the table, read once a build.
actions_keys :: proc(app: ^App) {
	for a in Action {
		if ui.command_pressed(ACTIONS[a], !action_enabled(app, a)) { action_run(app, a) }
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
