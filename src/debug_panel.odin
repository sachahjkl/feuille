package feuille

// The program's own panel in the toolkit's debug window (Ctrl+Alt+Shift+D, gt:debug): the document as the worker last
// posted it, the caches, the view's switches, and acts a person or a tool presses. It reads only what the interface's
// thread holds already: no system call, nothing asked of the worker but through its asks.

import debug "gt:debug"

debug_panel_register :: proc(app: ^App) {
	debug.panel(&app.main.state, "Feuille", debug_panel, app)
}

@(private = "file")
debug_panel :: proc(app: ^App) {
	if debug.section("Document") {
		s := app.snapshot
		if s == nil {
			debug.note("No document")
		} else {
			debug.watch("path", s.path)
			debug.watch("revision", s.revision)
			debug.watch("pages", len(s.pages))
			debug.watch("edited", s.edited)
			debug.watch("stamp", s.stamp)
			debug.watch("undo / redo", [2]bool{s.can_undo, s.can_redo})
		}
		debug.watch("pending", app.pending)
		debug.watch("failure", app.failure)
		if s != nil && debug.act("Open again") { app_open_file(app, s.path, "") }
	}
	if debug.section("Caches") {
		debug.watch("page pictures", len(app.pictures))
		debug.watch("thumbnails", len(app.thumbs))
		if debug.act("Drop the pictures") {
			pictures_clear(app)
			thumbs_clear(app)
		}
	}
	if debug.section("View") {
		debug.toggle("form layer", &app.layer)
		debug.toggle("thumbnails", &app.thumbs_shown)
		debug.choice("tool", &app.tool)
		debug.watch("selected", app.selected_at)
	}
}
