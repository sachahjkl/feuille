package feuille

// The program's state: the window, its settings, the worker, and the document as the interface shows it. Everything
// here belongs to the interface's thread; the worker's answers arrive through ui.post (on_opened, on_open_failed,
// on_picture). Reading the preferences, the themes file and the last crash at the start is the one exception to "no
// file on this thread": they size and style the window before it exists.

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import config "gt:config"
import crash_bar "gt:crash_bar"
import "gt:devtools"
import host "gt:host"
import i18n "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:render"
import setup "gt:setup"
import "gt:ui"
import pdf "pdf"

// feuille's own texts in each language it speaks besides English (the toolkit's are the toolkit's).
PROGRAM_CATALOGUES :: []i18n.Catalog{{"fr", #load("../i18n/fr.txt", string)}}
CHANGELOG :: #load("../CHANGELOG.md", string)

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
	shared:        host.Shared,
	main:          host.Host,
	worker:        Worker,
	headless:      bool,   // the tests: no window of the system, no system dialog, no file of the person's
	frame:         u64,
	quit:          bool,
	launch_after:  string,   // the program started again once this one ends (an update, Restart); owned

	// the settings and what follows them
	prefs:         config.Prefs,
	prefs_writer:  config.User_Writer,
	prefs_path:    string,   // owned
	settings:      Settings,
	standard:      prefs_page.Standard_Watch,
	themes_file:   prefs_page.Themes_File,
	theme_shown:   ui.Theme_Shown,
	placement:     prefs_page.Placement_Keeper,
	licence:       prefs_page.Licence,
	updates:       prefs_page.Updates,
	changelog:     prefs_page.Changelog,
	settings_open: bool,
	settings_page: prefs_page.Page,

	// the window's tools
	keymap:        ui.Keymap,
	views:         ui.Views,
	palette:       ui.Command_Palette,
	palette_state: Palette_State,
	sheet:         ui.Shortcuts_Sheet,
	announcer:     ui.Announcer,
	crash_bar:     crash_bar.Bar,
	devtools:      ^devtools.Server,
	status:        string,   // a message of the status bar (owned), until status_until (ui clock, ms)
	status_until:  f64,

	// the document
	snapshot:      ^Snapshot,     // nil: none open
	pending:       Pending,
	asked:         string,        // the file of the open under way, or of the password asked
	failure:       pdf.Error,     // why the last open failed (None: it did not)
	failed:        string,        // the file it failed on
	password:      ui.Line_Edit,
	reveal:        bool,
	wrong:         bool,          // the password given was refused
	focus_password: bool,         // the next build gives the password field the keyboard

	// the view of it
	layer:         bool,          // the interactive layer drawn (src/md/features/masked-opening.md)
	zone:          ui.Zoom_Zone,
	layout:        Layout,
	to_top:        bool,          // a new document: the view goes back to its start
	go_to:         int,           // a page to bring to the top of the view (-1: none)
	current:       int,           // the page at the middle of the view, as the last build found it
	pictures:      map[u64]Shown,
	last_ask:      [dynamic]Render_Ask,
}

App_Options :: struct {
	path:       string,     // a file to open at once ("": none)
	headless:   bool,
	size:       [2]int,     // the window's (0: the settings')
	pref_args:  []string,   // --pref name=value
	last_crash: string,     // the last session's crash report ("": none)
}

// Pictures kept beyond the pages in view: the oldest seen go past this count.
PICTURES_KEPT :: 48

app_open :: proc(o: App_Options) -> ^App {
	context.allocator = runtime.heap_allocator()
	app := new(App)
	app.headless = o.headless
	app.go_to = -1
	crash_bar.init(&app.crash_bar, o.last_crash)
	_, problems := prefs_open(&app.prefs, o.pref_args, read_file = !o.headless)
	for p in problems { log.warnf("feuille: %s", p) }
	app.settings = prefs_read(&app.prefs)
	app.layer = app.settings.layer
	if !o.headless {
		prefs_page.language_start(&app.prefs, PROGRAM_CATALOGUES)
		app.prefs_path = prefs_file(context.allocator)
		config.user_writer_start(&app.prefs_writer, &app.prefs, app.prefs_path)
	}
	prefs_page.themes_file_init(&app.themes_file, o.headless ? "" : themes_file(), themes())

	size := o.size != {} ? o.size : app.settings.size
	if !host.host_open(&app.main, &app.shared, {title = APP_TITLE, size = size, integrated_title = !o.headless && !app.settings.system_title, headless = o.headless}, view_build, app) {
		app_free(app)
		return nil
	}
	h := &app.main
	if !o.headless {
		ui.views_init(&app.views, {path = views_path()})
	} else {
		ui.views_init(&app.views, {})
	}
	ui.set_views(&h.state, &app.views)
	ui.views_set_windows(&app.views, host.view_windows(h.shared))
	ui.keymap_known(&app.keymap, slice.enumerated_array(&ACTIONS))
	ui.keymap_use(&h.state, &app.keymap)
	app.announcer = {mode = app.settings.messages, window = h.win, state = &h.state}
	prefs_page.standard_watch(&app.standard, &app.prefs, &h.state, {renderer = &app.shared.r, fonts = &app.shared.fonts, partial_redraw = &h.partial_redraw, pacer = &h.pacer, keymap = &app.keymap})
	h.state.icon_font = ui.lucide_icons()
	h.params = app_params
	h.input = app_input
	h.close_asked = proc(h: ^host.Host) { (^App)(h.user).quit = true }
	licence_init(app)
	if !o.headless {
		ui.set_file_dialogs(&h.state, .System)
		platform.drop_target_enable(h.win, true)
		platform.set_app_id(APP_NAME)
		app.devtools = devtools.start_from_env(h.win, APP_NAME)
		h.before_input = proc(h: ^host.Host) { app := (^App)(h.user); devtools.service(app.devtools, &h.state, &app.shared.r) }
		prefs_page.placement_restore(&app.placement, &app.prefs, h.win)
		updates_init(app)
		app.changelog.english = CHANGELOG
		prefs_page.changelog_after_update(&app.changelog, &app.prefs, APP_VERSION, &app.announcer, proc(user: rawptr) {
			app := (^App)(user)
			app.settings_open = true
			prefs_page.show(&app.settings_page, &app.prefs, settings_options(app), prefs_page.CHANGELOG_PAGE)
		}, app)
	}
	palette_init(app)
	app.pictures = make(map[u64]Shown)
	app.last_ask = make([dynamic]Render_Ask)
	worker_start(&app.worker, {state = &h.state, user = app, opened = on_opened, failed = on_open_failed, picture = on_picture})
	if o.path != "" { app_open_file(app, o.path, "") }
	return app
}

// One turn of the program's loop after the wait: the window's frame and what the program follows between frames.
app_step :: proc(app: ^App) {
	app_updates_follow(app)
	if !app.headless {
		prefs_page.placement_track(&app.placement, &app.prefs, app.main.win, ui.now_ms())
		config.user_writer_save(&app.prefs_writer, &app.prefs)
		if config.user_writer_failed(&app.prefs_writer) { say(app, i18n.tr("The preferences cannot be written")) }
	}
	if !app.quit && !platform.is_closed(app.main.win) { host.host_frame(&app.main) }
}

app_close :: proc(app: ^App) {
	context.allocator = runtime.heap_allocator()
	if !app.headless && app.main.win != nil { prefs_page.placement_keep(&app.placement, &app.prefs, app.main.win) }
	ui.post_close(&app.main.state)
	worker_stop(&app.worker)
	prefs_page.updates_stop(&app.updates)
	devtools.stop(app.devtools)
	pictures_clear(app)   // (before the renderer goes: the textures are its)
	// (a dialog's answer comes to the window's state: the chores end before it does)
	ui.chores_stop()
	prefs_page.changelog_destroy(&app.changelog)
	crash_bar.destroy(&app.crash_bar)
	ui.views_destroy(&app.views)
	host.host_close(&app.main)
	launch := app.launch_after
	app.launch_after = ""
	app_free(app)
	if launch != "" {
		if !setup.launch(launch, nil) { log.errorf("feuille: %s does not start", launch) }
		delete(launch)
	}
}

@(private = "file")
app_free :: proc(app: ^App) {
	delete(app.pictures)
	delete(app.last_ask)
	snapshot_free(app.snapshot)
	layout_destroy(&app.layout)
	delete(app.asked)
	delete(app.failed)
	delete(app.status)
	ui.line_edit_destroy(&app.password)
	ui.zoom_zone_destroy(&app.zone)
	ui.palette_destroy(&app.palette)
	ui.shortcuts_sheet_destroy(&app.sheet)
	prefs_page.destroy(&app.settings_page)
	prefs_page.themes_file_destroy(&app.themes_file)
	licence_destroy(app)
	settings_free(&app.settings)
	prefs_page.standard_unwatch(&app.standard)
	ui.keymap_destroy(&app.keymap)
	if !app.headless { config.user_writer_stop(&app.prefs_writer, &app.prefs) }
	prefs_page.placement_keeper_destroy(&app.placement)
	config.prefs_destroy(&app.prefs)
	delete(app.prefs_path)
	free(app)
}

// What each build is given: the theme of the settings and the base style.
@(private = "file")
app_params :: proc(h: ^host.Host, bp: ^ui.Build_Params) {
	app := (^App)(h.user)
	choice := prefs_page.appearance_choice(app.settings.look)
	if ui.theme_show(&app.shared.theme, app.themes_file.all[:], choice, &app.theme_shown, render.blend_space(&app.shared.r)) {
		platform.set_dark_title(h.win, !app.theme_shown.light)
		h.background = ui.theme_lookup(&app.shared.theme, {}, "background")
	}
	bp.base = ui.Style{pref = {.X = ui.text_size(), .Y = ui.px(28)}, font = app.shared.font, font_size = app.settings.look.font_size, text_pad = 6, cursor = .Arrow}
}

// window.system_title: the system's title bar, or feuille's own, switched at once.
app_title_follow :: proc(app: ^App) {
	if !app.headless { platform.set_integrated_title(app.main.win, !app.settings.system_title) }
}

// Asks the worker for `path`. The document shown stays until the new one is open.
app_open_file :: proc(app: ^App, path, password: string) {
	if app.asked != path {
		delete(app.asked)
		app.asked = strings.clone(path)
	}
	app.pending = .Loading
	app.settings_open = false
	worker_open(&app.worker, path, password)
	host.host_settle(&app.main)
}

// Shows a message in the status bar for a few seconds.
say :: proc(app: ^App, format: string, args: ..any) {
	delete(app.status)
	app.status = fmt.aprintf(format, ..args)
	app.status_until = ui.now_ms() + STATUS_SHOWN_MS
	ui.wake_within(&app.main.state, STATUS_SHOWN_MS + 1)
}

STATUS_SHOWN_MS :: 3000

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
	app.current = 0
	app.layer = app.settings.layer   // (each document opens as the settings say: masked, unless asked)
	ui.line_edit_clear(&app.password)
	platform.set_title(app.main.win, strings.concatenate({filepath.base(app.snapshot.path), " – ", APP_TITLE}, context.temp_allocator))
	host.host_settle(&app.main)
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
		app.focus_password = true
		ui.line_edit_clear(&app.password)
	} else {
		app.pending = .None
		app.failure = f.error
		delete(app.failed)
		app.failed = strings.clone(f.path)
		// (a document stays shown: the failure is said in the status bar; with none, the empty view says it)
		if app.snapshot != nil { say(app, i18n.tr("%s cannot be opened: %s"), filepath.base(f.path), failure_text(f.error)) }
	}
	host.host_settle(&app.main)
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
	host.host_settle(&app.main)
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

// A PDF dropped on the window opens; other files are refused at the drop.
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

// feuille's own theme, first of the list: a warm dark and a paper light, the accent of the autumn leaf.
THEME_FEUILLE :: ui.Theme_Def{"Feuille",
	{{0x100d0bff, 0x161210ff, 0x1d1815ff, 0x1d1815ff, 0x272019ff, 0x30281fff}, {0x5e554cff, 0x948a7fff, 0xefe7deff, 0xfffaf3ff},
		{0xf59a3cff, 0x8fa9c9ff, 0xa99bc4ff, 0x56a55eff, 0xf5b324ff, 0xe5534bff, 0x95c3c8ff, 0xd9907aff}},
	{{0xeee7dcff, 0xf8f3ebff, 0xffffffff, 0xffffffff, 0xf1eadfff, 0xe3dacdff}, {0xa59b8fff, 0x6f665cff, 0x1d1915ff, 0x000000ff},
		{0xc2560dff, 0x3d6a9eff, 0x6b56a3ff, 0x2f8f46ff, 0xc98a10ff, 0xd03b31ff, 0x2f7c86ff, 0xa64a42ff}},
	.Both, nil, false, 0}

// The themes the window can show: feuille's, then the toolkit's (gui_toolkit docs/themes.md).
themes :: proc() -> []ui.Theme_Def {
	@(static) list: [len(ui.THEMES) + 1]ui.Theme_Def
	if list[0].name == "" {
		list[0] = THEME_FEUILLE
		copy(list[1:], ui.THEMES[:])
	}
	return list[:]
}
