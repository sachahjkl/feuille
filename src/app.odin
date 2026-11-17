package feuille

// The program's state: the window, the worker, and the document as the interface shows it. Everything here belongs to
// the interface's thread; the worker's answers arrive through ui.post (on_opened, on_open_failed, on_picture).

import "base:runtime"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import host "gt:host"
import "gt:platform"
import "gt:render"
import "gt:ui"
import pdf "pdf"

// Where an open stands (src/md/README.md, "State machines"). The document shown stays through Loading and Locked.
Pending :: enum u8 {
	None,
	Loading,   // the worker reads the file
	Locked,    // the file wants a password: the window asks for it
}

// A page's picture on screen, by page identity: the newest one rendered, whatever its size (a stale one stays drawn
// until its replacement comes).
Shown :: struct {
	tex:   render.Texture,
	size:  [2]int,
	layer: bool,
	seen:  u64,   // the frame it was last drawn in
}

App :: struct {
	shared:   host.Shared,
	main:     host.Host,
	worker:   Worker,
	keymap:   ui.Keymap,
	headless: bool,   // the tests: no window of the system, no system dialog
	frame:    u64,

	// the document
	snapshot: ^Snapshot,     // nil: none open
	pending:  Pending,
	asked:    string,        // the file of the open under way, or of the password asked
	failure:  pdf.Error,     // why the last open failed (None: it did not)
	failed:   string,        // the file it failed on
	password: ui.Line_Edit,
	reveal:   bool,
	wrong:    bool,          // the password given was refused

	// the view
	layer:    bool,          // the interactive layer drawn (src/md/features/masked-opening.md)
	zone:     ui.Zoom_Zone,
	layout:   Layout,
	to_top:   bool,          // a new document: the view goes back to its start
	pictures: map[u64]Shown,
	last_ask: [dynamic]Render_Ask,
}

App_Options :: struct {
	path:     string,   // a file to open at once ("": none)
	headless: bool,
	size:     [2]int,   // the window's (0: the default)
}

APP_SIZE_DEFAULT :: [2]int{900, 1000}
// Pictures kept beyond the pages in view: the oldest seen go past this count.
PICTURES_KEPT :: 48

app_open :: proc(o: App_Options) -> ^App {
	context.allocator = runtime.heap_allocator()
	app := new(App)
	app.headless = o.headless
	size := o.size != {} ? o.size : APP_SIZE_DEFAULT
	if !host.host_open(&app.main, &app.shared, {title = APP_TITLE, size = size, integrated_title = !o.headless, headless = o.headless}, view_build, app) {
		free(app)
		return nil
	}
	app.main.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	app.main.input = app_input
	ui.keymap_known(&app.keymap, slice.enumerated_array(&ACTIONS))
	ui.keymap_use(&app.main.state, &app.keymap)
	if !o.headless {
		ui.set_file_dialogs(&app.main.state, .System)
		platform.drop_target_enable(app.main.win, true)
	}
	app.pictures = make(map[u64]Shown)
	app.last_ask = make([dynamic]Render_Ask)
	worker_start(&app.worker, {state = &app.main.state, user = app, opened = on_opened, failed = on_open_failed, picture = on_picture})
	if o.path != "" { app_open_file(app, o.path, "") }
	return app
}

app_close :: proc(app: ^App) {
	context.allocator = runtime.heap_allocator()
	ui.post_close(&app.main.state)
	worker_stop(&app.worker)
	pictures_clear(app)   // (before the renderer goes: the textures are its)
	delete(app.pictures)
	delete(app.last_ask)
	snapshot_free(app.snapshot)
	layout_destroy(&app.layout)
	delete(app.asked)
	delete(app.failed)
	ui.line_edit_destroy(&app.password)
	ui.zoom_zone_destroy(&app.zone)
	ui.keymap_destroy(&app.keymap)
	host.host_close(&app.main)
	free(app)
}

// Asks the worker for `path`. The document shown stays until the new one is open.
app_open_file :: proc(app: ^App, path, password: string) {
	if app.asked != path {
		delete(app.asked)
		app.asked = strings.clone(path)
	}
	app.pending = .Loading
	worker_open(&app.worker, path, password)
	host.host_settle(&app.main)
}

// The window's frames after a change the worker posted.
@(private = "file")
redraw :: proc(app: ^App) { host.host_settle(&app.main) }

@(private = "file")
on_opened :: proc(data: rawptr, _: u64) {
	o := (^Opened)(data)
	defer free(o)
	app := (^App)(o.user)
	snapshot_free(app.snapshot)
	app.snapshot = o.snapshot
	pictures_clear(app)
	clear(&app.last_ask)
	app.pending = .None
	app.failure = .None
	app.wrong = false
	app.to_top = true
	ui.line_edit_clear(&app.password)
	platform.set_title(app.main.win, strings.concatenate({filepath.base(app.snapshot.path), " – ", APP_TITLE}, context.temp_allocator))
	redraw(app)
}

@(private = "file")
on_open_failed :: proc(data: rawptr, _: u64) {
	f := (^Open_Failure)(data)
	defer open_failure_free(f)
	app := (^App)(f.user)
	// (an answer to an open that another one replaced: the newer one speaks)
	if f.path != app.asked { return }
	if f.error == .Password {
		app.wrong = app.pending == .Locked || ui.line_edit_string(&app.password) != ""
		app.pending = .Locked
		ui.line_edit_clear(&app.password)
	} else {
		app.pending = .None
		app.failure = f.error
		delete(app.failed)
		app.failed = strings.clone(f.path)
	}
	redraw(app)
}

@(private = "file")
on_picture :: proc(data: rawptr, _: u64) {
	p := (^Picture)(data)
	defer picture_free(p)
	app := (^App)(p.user)
	if app.snapshot == nil || p.revision != app.snapshot.revision { return }
	r := &app.shared.r
	s, had := app.pictures[p.id]
	if had && s.size != p.size {
		render.destroy_texture(r, s.tex)
		had = false
	}
	if !had { s.tex = render.create_texture_rgba(r, p.size.x, p.size.y) }
	render.update_texture_rgba(r, s.tex, 0, 0, p.size.x, p.size.y, p.rgba)
	s.size, s.layer, s.seen = p.size, p.layer, app.frame
	app.pictures[p.id] = s
	pictures_trim(app)
	redraw(app)
}

@(private = "file")
pictures_clear :: proc(app: ^App) {
	for _, s in app.pictures { render.destroy_texture(&app.shared.r, s.tex) }
	clear(&app.pictures)
}

// Past PICTURES_KEPT, the pictures seen longest ago go. Runs when a picture comes: over the pictures kept, not the pages.
@(private = "file")
pictures_trim :: proc(app: ^App) {
	for len(app.pictures) > PICTURES_KEPT {
		oldest: u64
		oldest_seen := max(u64)
		for id, s in app.pictures {
			if s.seen < oldest_seen { oldest, oldest_seen = id, s.seen }
		}
		render.destroy_texture(&app.shared.r, app.pictures[oldest].tex)
		delete_key(&app.pictures, oldest)
	}
}

// A PDF dropped on the window opens; other files are refused at the pointer.
@(private = "file")
app_input :: proc(h: ^host.Host, events: []platform.Event) -> []platform.Event {
	app := (^App)(h.user)
	kept := make([dynamic]platform.Event, 0, len(events), context.temp_allocator)
	for e in events {
		#partial switch e.kind {
		case .Drop_Enter, .Drop_Over, .Drop_Leave, .Drop:
			path := dropped_pdf(h.win)
			// (Linux gives a drag's files at its drop only: until then, take it, and look at the drop)
			effect: Maybe(platform.Drop_Effect) = .Copy
			if e.kind == .Drop {
				if path != "" { app_open_file(app, path, "") } else { effect = nil }
			}
			platform.drop_set_effect(h.win, effect)
			if e.kind == .Drop || e.kind == .Drop_Leave { platform.drop_data_release(h.win) }
			continue
		}
		append(&kept, e)
	}
	return kept[:]
}

// The first PDF of the drag's files ("": none).
@(private = "file")
dropped_pdf :: proc(w: ^platform.Window) -> string {
	d := platform.drop_data(w)
	if d == nil { return "" }
	for f in d.files {
		if strings.has_suffix(strings.to_lower(f, context.temp_allocator), ".pdf") { return f }
	}
	return ""
}
