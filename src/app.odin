package feuille

// The program's state: the window, its settings, the worker, and the document as the interface shows it. Everything
// here belongs to the interface's thread; the worker's answers arrive through ui.post (on_opened, on_open_failed,
// on_picture). Reading the preferences, the themes file, the memory of the documents (recent.odin) and the last crash
// at the start is the one exception to "no file on this thread": they size and style the window, and say what it
// opens, before it is shown. Whatever else waits on the system is a task (launch.odin, integration.odin).

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import config "gt:config"
import crash_bar "gt:crash_bar"
import desktop "gt:desktop"
import "gt:devtools"
import "gt:font"
import host "gt:host"
import i18n "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import process "gt:process"
import "gt:render"
import setup "gt:setup"
import tasks "gt:tasks"
import "gt:ui"
import pdf "gt:pdf"

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
	tex:     render.Texture,
	size:    [2]int,
	layer:   bool,
	version: u64,   // the page's content version it shows
	seen:    u64,   // the frame it was last drawn in
}

// A stamp being written: the window's field over it (src/md/features/marks.md). Its states: none; open (the field
// over the stamp, or at the point clicked for a new one); then committed or given up.
Text_Edit :: struct {
	open:   bool,
	id:     u64,       // the page
	index:  int,       // the stamp on it (-1: a new one)
	box:    [4]f32,    // shares of the page shown
	before: string,    // its words when opened (owned): a commit of the same words and style changes nothing
	style:  pdf.Stamp, // its style when opened
	field:  ui.Line_Edit,
	focus:  bool,      // the next build gives the field the keyboard
}

// The size of a stamp before anything is chosen (black sans serif on nothing), in points.
STAMP_SIZE :: 14

App :: struct {
	shared:        host.Shared,
	main:          host.Host,
	worker:        Worker,
	headless:      bool,   // the tests: no window of the system, no system dialog, no file of the person's
	frame:         u64,
	quit:          bool,
	launch_after:  string,   // the program started again once this one ends (an update, Restart); owned
	exe:           string,   // this program's file, read once at the start (an update puts a new one in its place); owned
	pool:          tasks.Pool,   // what waits on the system: the launches, the applications of "Open with" (launch.odin)
	install:       prefs_page.Install,   // the install: its offer, its dialog, the settings' page (integration.odin)
	opened:        [dynamic]string,      // headless: what a launch would have started (owned)

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
	failure:       Open_Error,    // why the last open failed (None: it did not)
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
	frame_asks:    [dynamic]Render_Ask,   // the pictures this frame wants (send_asks)
	selected:      u64,           // the page the edits act on (0: none)
	selected_at:   int,           // its index, as the last snapshot said (the next page is selected when it goes)
	thumbs_shown:  bool,
	thumbs:        map[u64]Shown, // the strip's pictures, by page
	thumb_layout:  Layout,
	drag_id:       u64,           // a thumbnail dragged (0: none)
	drop_at:       int,           // where it would go, an index
	tool:          Tool,          // the marking tool on (marks.odin)
	text:          Text_Edit,
	style:         pdf.Stamp,     // the style of the stamp written and of the next ones (its text unused)
	ink:           pdf.Shape,     // the style of the next shapes (its kind and points unused)
	marker:        [4]u8,         // the highlighter's colour
	chosen:        Mark_Ref,      // the mark the style bar and Delete act on (kind None: none)
	gesture:       Gesture,       // a press of a tool on a page, until its release
	sign:          Sign_State,    // the signature, its dialog, its preview thread (signature_view.odin)
	go_jump:       bool,          // go_to is reached at once, not scrolled to (a document opened at its last page)
	memory:        Memory,        // the recent PDFs, each one's page and zoom (recent.odin)
	reopening:     bool,          // the open under way is the last document's, at the start: a failure is not said
	open_with:     ui.Open_With,  // the applications that open the PDF, with their icons, for the menus' "Open with"
	shell_menu:    ui.Shell_Menu, // the system's shell actions for the open PDF (menus.odin)
	doc_watch:     Doc_Watch,     // the document's file followed on the disk (file_watch.odin)
	menu_was_open: bool,

	// what waits for an answer of a confirmation
	leave_next:    Leave_Next,
	leave_path:    string,        // the file to open once the edits are left (owned)
	overwrite:     string,        // the original a save writes over, once confirmed (owned)
}

// The selected page's index in the snapshot (-1: none).
selected_index :: proc(app: ^App) -> int {
	s := app.snapshot
	if s == nil { return -1 }
	// (the index the snapshot gave first: a pass over the pages only when it moved)
	if i := app.selected_at; i >= 0 && i < len(s.pages) && s.pages[i].id == app.selected { return i }
	for p, i in s.pages { if p.id == app.selected { return i } }
	return -1
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
	app.style = {size = STAMP_SIZE}
	app.ink, app.marker = SHAPE_STYLE, HIGHLIGHT_INK
	app.go_to = -1
	// (read once: after an update the file is the new program, and a restart reads no file on this thread)
	app.exe = strings.clone(process.executable_path())
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
	// (the announcer is set up with the window: the install says through it when the desktop refuses a setting)
	prefs_page.install_init(&app.install, &app.prefs, setup_options(), &app.announcer)
	memory_open(app)
	// (the tests read none of the person's associations: no application)
	if o.headless { app.open_with.handlers_of = proc(_: string, _: runtime.Allocator) -> []desktop.Handler { return nil } }

	// (before the first window: Wayland and the taskbar group the windows by it)
	if !o.headless { platform.set_app_id(APP_NAME) }
	size := o.size != {} ? o.size : app.settings.size
	if !host.host_open(&app.main, &app.shared, {title = APP_TITLE, size = size, integrated_title = !o.headless && !app.settings.system_title, headless = o.headless}, view_build, app) {
		app_free(app)
		return nil
	}
	h := &app.main
	// (offered where the system can draw a title bar: Windows, X11, a Wayland compositor with server-side ones)
	if r := config.ref_of(&app.prefs, prefs_page.SYSTEM_TITLE_PREF); r != config.NO_REF {
		config.entry(&app.prefs, r).def.hidden = !platform.system_title_available(h.win)
	}
	// (the vendor signs the install's dialog and page; a texture of this window's renderer)
	prefs_page.install_vendor_mark(&app.install, &app.shared.r, VENDOR_MARK_PNG)
	// (the person's emoji font, read at the start: the tests' fonts are compiled in)
	if !o.headless {
		if path := config.string_of(&app.prefs, prefs_page.EMOJI_FONT_PREF); path != "" { font.set_emoji_source(&app.shared.fonts, path) }
	}
	tasks.start(&app.pool, {threads = 1, grow = 2})
	if !o.headless {
		ui.views_init(&app.views, {path = views_path()})
	} else {
		ui.views_init(&app.views, {})
	}
	ui.set_views(&h.state, &app.views)
	ui.views_set_windows(&app.views, host.view_windows(h.shared))
	ui.keymap_known(&app.keymap, slice.enumerated_array(&ACTIONS))
	ui.keymap_use(&h.state, &app.keymap)
	app.announcer = {mode = announce_mode(app), window = h.win, state = &h.state}
	prefs_page.standard_watch(&app.standard, &app.prefs, &h.state, {renderer = &app.shared.r, fonts = &app.shared.fonts, partial_redraw = &h.partial_redraw, pacer = &h.pacer, keymap = &app.keymap})
	h.state.icon_font = ui.lucide_icons()
	h.params = app_params
	h.input = app_input
	// (an edited document asks first: the window stays until the answer)
	h.close_asked = proc(h: ^host.Host) { leave_document((^App)(h.user), .Quit) }
	licence_init(app)
	if !o.headless {
		// (what each file dialog remembers: read on the chores, written by its own thread)
		ui.file_dialog_memory(&h.state, file_dialogs_path())
		platform.drop_target_enable(h.win, true)
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
	app.thumbs = make(map[u64]Shown)
	app.thumbs_shown = true
	app.last_ask = make([dynamic]Render_Ask)
	app.frame_asks = make([dynamic]Render_Ask)
	worker_start(&app.worker, {state = &h.state, user = app, opened = on_opened, failed = on_open_failed, picture = on_picture, saved = on_saved, printed = on_printed, window = o.headless ? nil : h.win})
	sign_init(app)
	doc_watch_start(app)
	debug_panel_register(app)
	switch {
	case o.path != "":
		app_open_file(app, o.path, "")
	// (no file given: the last one again, unless the settings say no)
	case app.settings.reopen_last && len(app.memory.recent) > 0:
		app_open_file(app, app.memory.recent[0], "")
		app.reopening = true
	}
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
	doc_watch_stop(app)
	worker_stop(&app.worker)
	sign_close(app)   // (its texture is the renderer's: before the window goes)
	// (their answers find the window closed: each task frees what it was given)
	tasks.stop(&app.pool)
	prefs_page.updates_stop(&app.updates)
	devtools.stop(app.devtools)
	pictures_clear(app)   // (before the renderer goes: the textures are its)
	thumbs_clear(app)
	ui.shell_menu_destroy(&app.shell_menu)   // (its icons' textures are this renderer's)
	ui.open_with_destroy(&app.open_with)     // (so are its applications' icons)
	// (a dialog's answer comes to the window's state: the chores end before it does)
	ui.chores_stop()
	// (the install's thread waited for, before the window's state goes; its vendor's mark is this renderer's)
	prefs_page.install_end(&app.install)
	prefs_page.changelog_destroy(&app.changelog)
	crash_bar.destroy(&app.crash_bar)
	ui.views_destroy(&app.views)
	host.host_close(&app.main)
	// (the window closed and the instance let go: the installed copy the install opened starts now, and owns it)
	prefs_page.install_launch(&app.install)
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
	delete(app.thumbs)
	delete(app.last_ask)
	delete(app.frame_asks)
	snapshot_free(app.snapshot)
	layout_destroy(&app.layout)
	layout_destroy(&app.thumb_layout)
	text_edit_close(app)
	ui.line_edit_destroy(&app.text.field)
	delete(app.gesture.points)
	delete(app.leave_path)
	delete(app.overwrite)
	delete(app.asked)
	delete(app.failed)
	delete(app.status)
	delete(app.exe)
	for o in app.opened { delete(o) }
	delete(app.opened)
	memory_close(app)   // (what changed is written: the stores' workers end)
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

// Where "Saved" and its kin are said: the settings' choice; a headless window (the tests) keeps them in itself, never
// on the person's desktop.
announce_mode :: proc(app: ^App) -> ui.Announce_Mode {
	return app.headless ? .Window : app.settings.messages
}

// window.system_title: the system's title bar, or feuille's own, switched at once.
app_title_follow :: proc(app: ^App) {
	if !app.headless { platform.set_integrated_title(app.main.win, !app.settings.system_title) }
}

// Asks the worker for `path`. The document shown stays until the new one is open.
app_open_file :: proc(app: ^App, path, password: string) {
	// (what the App keeps is the heap's, whoever calls: a test, a dialog's answer, a drop)
	context.allocator = runtime.heap_allocator()
	if app.asked != path {
		delete(app.asked)
		app.asked = strings.clone(path)
	}
	app.pending = .Loading
	app.settings_open = false
	app.reopening = false   // (an open asked now is the person's: its failure is said)
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

// A new snapshot: a document opened (the view starts again), or the one shown edited (the view, the pictures of the
// pages that did not change and the selection stay; a page removed hands the selection to the one after it).
@(private = "file")
on_opened :: proc(data: rawptr, _: u64) {
	o := (^Opened)(data)
	defer free(o)
	app := (^App)(o.user)
	old := app.snapshot
	app.snapshot = o.snapshot
	defer snapshot_free(old)
	s := app.snapshot
	clear(&app.last_ask)
	if s.opened {
		pictures_clear(app)
		thumbs_clear(app)
		text_edit_close(app)
		app.pending = .None
		app.failure = .None
		app.wrong = false
		app.to_top = true
		app.current = 0
		app.layer = app.settings.layer   // (each document opens as the settings say: masked, unless asked)
		app.tool, app.chosen = .None, {}
		app.selected, app.selected_at = s.pages[0].id, 0
		app.reopening = false
		ui.line_edit_clear(&app.password)
		// (the page it showed last, at once; its zoom is the zone's memory, by its path)
		if page := recent_page(app, s.path); page > 0 && page < len(s.pages) {
			go_to_page(app, page)
			app.go_jump = true
		}
		app.memory.page_kept = -1
		recent_add(app, s.path)
	} else {
		at := selected_index(app)
		if at < 0 && len(s.pages) > 0 {
			at = min(app.selected_at, len(s.pages) - 1)
			app.selected = s.pages[at].id
		}
		app.selected_at = at
		// (a text edit open on a page that changed under it is let go)
		if app.text.open && !page_exists(s, app.text.id) { text_edit_close(app) }
	}
	doc_watch_follow(app, s.path, s.stamp)
	app_title(app)
	host.host_settle(&app.main)
}

@(private = "file")
page_exists :: proc(s: ^Snapshot, id: u64) -> bool {
	for p in s.pages { if p.id == id { return true } }
	return false
}

// The window's title: the file's name, a mark while it holds unsaved edits.
@(private = "file")
app_title :: proc(app: ^App) {
	s := app.snapshot
	if s == nil { return }
	mark := s.edited ? "• " : ""
	platform.set_title(app.main.win, strings.concatenate({mark, filepath.base(s.path), " – ", APP_TITLE}, context.temp_allocator))
}

@(private = "file")
on_saved :: proc(data: rawptr, _: u64) {
	s := (^Saved)(data)
	defer saved_free(s)
	app := (^App)(s.user)
	name := filepath.base(s.path)
	switch {
	case !s.ok:     say(app, i18n.tr("%s cannot be written"), name)
	case s.extract: ui.announce(&app.announcer, .Good, fmt.tprintf(i18n.tr("Saved the page as %s"), name))
	case:           ui.announce(&app.announcer, .Good, fmt.tprintf(i18n.tr("Saved %s"), name))
	}
	host.host_settle(&app.main)
}

@(private = "file")
on_printed :: proc(data: rawptr, _: u64) {
	p := (^Printed)(data)
	defer free(p)
	app := (^App)(p.user)
	switch p.status {
	case .Printed:     ui.announce(&app.announcer, .Good, i18n.tr("Sent to the printer"))
	case .Cancelled:
	case .Unsupported: say(app, i18n.tr("Printing is not available here"))
	case .Failed:      say(app, i18n.tr("The document could not be printed"))
	}
	host.host_settle(&app.main)
}

// The stamp field closed, its words given up.
text_edit_close :: proc(app: ^App) {
	delete(app.text.before)
	app.text.before = ""
	app.text.open = false
}

// The field's words, committed: one undoable edit when its words or its style changed. A new stamp left empty is
// nothing; an old one emptied is removed.
text_edit_commit :: proc(app: ^App) {
	if !app.text.open { return }
	words := ui.line_edit_string(&app.text.field)
	style := app.style
	style.text = ""
	if app.text.index < 0 ? words != "" : (words != app.text.before || style != app.text.style) {
		at := [2]f32{app.text.box[0], app.text.box[1]}
		worker_edit(&app.worker, stamp_ask_make(&app.worker, app.text.id, app.text.index, style, words, at))
	}
	text_edit_close(app)
}

// The stamp of page `p` under `at` (shares of the page shown), the last drawn first; -1: none.
stamp_at :: proc(p: Snapshot_Page, at: [2]f32) -> int {
	#reverse for st, k in p.stamps {
		b := st.box
		if at.x >= b[0] && at.x <= b[2] && at.y >= b[1] && at.y <= b[3] { return k }
	}
	return -1
}

// A click of the text tool on page `p` at `at`: the stamp under it opens, its style becomes the tool's; elsewhere a
// new stamp opens there. What was being written is committed first.
stamp_click :: proc(app: ^App, p: Snapshot_Page, at: [2]f32) {
	text_edit_commit(app)
	k := stamp_at(p, at)
	app.text.open, app.text.id, app.text.index, app.text.focus = true, p.id, k, true
	if k >= 0 {
		st := p.stamps[k]
		// (the text tool's style only: a signature's font and effects stay on the stamp, the worker keeps them)
		app.style.font, app.style.size, app.style.color, app.style.background = st.stamp.font, st.stamp.size, st.stamp.color, st.stamp.background
		app.text.box = st.box
		app.text.before = strings.clone(st.stamp.text)
		ui.line_edit_set(&app.text.field, st.stamp.text)
	} else {
		app.text.box = {at.x, at.y, at.x, at.y}
		ui.line_edit_set(&app.text.field, "")
	}
	app.text.style = app.style
	app.text.style.text = ""
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
		// (a file that is gone leaves the recent ones)
		if f.error == .File { recent_forget(app, f.path) }
		if app.reopening {
			// (the last document, gone since: the window starts empty, as with no last document)
			app.reopening = false
			host.host_settle(&app.main)
			return
		}
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
	cache := p.thumb ? &app.thumbs : &app.pictures
	r := &app.shared.r
	s, had := cache[p.id]
	if had && s.size != p.size {
		render.destroy_texture(r, s.tex)
		had = false
	}
	if !had { s.tex = render.create_texture_rgba(r, p.size.x, p.size.y) }
	render.update_texture_rgba(r, s.tex, 0, 0, p.size.x, p.size.y, p.rgba)
	s.size, s.layer, s.version, s.seen = p.size, p.layer, p.version, app.frame
	cache[p.id] = s
	cache_trim(app, cache, p.thumb ? THUMBS_KEPT : PICTURES_KEPT)
	host.host_settle(&app.main)
}

// Thumbnails kept beyond those in view.
THUMBS_KEPT :: 200

pictures_clear :: proc(app: ^App) {
	for _, s in app.pictures { render.destroy_texture(&app.shared.r, s.tex) }
	clear(&app.pictures)
}

thumbs_clear :: proc(app: ^App) {
	for _, s in app.thumbs { render.destroy_texture(&app.shared.r, s.tex) }
	clear(&app.thumbs)
}

// Past `kept`, the pictures seen longest ago go. Runs when a picture comes: over the pictures kept, not the pages.
@(private = "file")
cache_trim :: proc(app: ^App, cache: ^map[u64]Shown, kept: int) {
	for len(cache) > kept {
		oldest: u64
		oldest_seen := max(u64)
		for id, s in cache {
			if s.seen < oldest_seen { oldest, oldest_seen = id, s.seen }
		}
		render.destroy_texture(&app.shared.r, cache[oldest].tex)
		delete_key(cache, oldest)
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
				if path != "" {
					open_asked(app, path)
				} else {
					effect = nil
				}
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
	.Both, nil, false, 0, {}}

// The themes the window can show: feuille's, then the toolkit's (gui_toolkit docs/themes.md).
themes :: proc() -> []ui.Theme_Def {
	@(static) list: [len(ui.THEMES) + 1]ui.Theme_Def
	if list[0].name == "" {
		list[0] = THEME_FEUILLE
		copy(list[1:], ui.THEMES[:])
	}
	return list[:]
}
