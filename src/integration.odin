package feuille

// feuille on the user's desktop (gui_toolkit's desktop and setup, through prefs_page.Install), and its single instance.
// The install puts the copy in a folder of its own, its launcher in the application menu with its icons, and feuille on
// the PATH; everything in the user's profile. The settings' Installation page shows the install and acts on it.
//
//   feuille --install     this copy installed for the user (no window)
//   feuille --uninstall   the install taken away; the settings stay (no window)
//   feuille --status      what is installed, and whether feuille runs (no window)
//   feuille --setup       the window, the install's dialog open
//
// On Windows a copy that is not installed offers the install at its start; on Linux Nix installs it, or
// `feuille --install`. One feuille runs per person: a second start hands its file to the first (app_message).

import "base:runtime"
import "core:os"
import "core:strings"
import "core:sync"
import desktop "gt:desktop"
import host "gt:host"
import i18n "gt:i18n"
import instance "gt:instance"
import "gt:platform"
import prefs_page "gt:prefs_page"
import setup "gt:setup"
import "gt:ui"

ICON_PNGS := [?]desktop.Icon{
	{16, #load("../assets/logo_16.png")},
	{32, #load("../assets/logo_32.png")},
	{64, #load("../assets/logo_64.png")},
	{128, #load("../assets/logo_128.png")},
	{256, #load("../assets/logo_256.png")},
}

// The vendor's mark in the install's dialog and page ("By <mark> Froment Software").
VENDOR_MARK_PNG :: #load("../assets/froment-software-64.png")

// The identity's derived strings are allocated: they are made once, for the whole run (the tasks and the setup's jobs
// share them).
@(private = "file") identity: desktop.Identity
@(private = "file") identity_once: sync.Once

feuille_identity :: proc() -> desktop.Identity {
	sync.once_do(&identity_once, proc() {
		id := desktop.identity_of("Froment Software", APP_TITLE, APP_NAME, runtime.heap_allocator())
		id.description = "Opens a PDF at once, its signatures, annotations and form fields hidden; arranges its pages and saves a copy."
		id.generic_name, id.categories = "PDF Reader", "Office;Viewer;Graphics;"
		id.keywords = "pdf;reader;viewer;document;pages;form;signature;"
		id.uninstall_arguments = "--setup"
		identity = id
	})
	return identity
}

// The files feuille opens: named always, whatever the boxes say (an install with the box off, and the uninstall, read
// them to know what to take away).
@(rodata) PDF_TYPES := [?]desktop.Document_Type{{extension = ".pdf", mime = "application/pdf", description = "PDF Document"}}

// feuille's own parts of an install: the PATH (on Windows with feuille.com, the console launcher the toolkit's build
// embeds: `feuille` typed in a terminal gives its output and exit code), and the PDF files it opens.
feuille_parts :: proc(o: ^desktop.Integration_Options) {
	o.add_to_path = true
	o.document_types = PDF_TYPES[:]
	o.open_documents = true
}

@(private = "file")
env_lookup :: proc(name: string) -> string { return os.get_env(name, context.temp_allocator) }

////////////////////////////////
// The install (prefs_page.Install: the offer, the dialog, the settings' Installation page)

setup_options :: proc() -> setup.Setup_Options {
	return setup.Setup_Options{
		identity = feuille_identity(), version = APP_VERSION, icons = ICON_PNGS[:],
		vendor_url = "https://froment.software",
		choices = SETUP_CHOICES[:], square = true, running = app_running, quit = app_quit,
		prepare = proc(o: ^desktop.Integration_Options, choices: []bool, user: rawptr) {
			feuille_parts(o)
			if len(choices) == len(SETUP_CHOICES) {
				o.add_to_path = choices[SETUP_PATH]
				o.open_documents = choices[SETUP_OPEN_PDF] || choices[SETUP_DEFAULT_PDF]
				o.default_documents = choices[SETUP_DEFAULT_PDF]
			}
			desktop.roots_from_env(o, env_lookup)   // (a test's places: nothing of the person's)
		},
	}
}

// The boxes of the install's dialog, by index.
SETUP_PATH        :: 0
SETUP_OPEN_PDF    :: 1   // in the file managers' Open with
SETUP_DEFAULT_PDF :: 2   // the PDF files' application (Windows: its Default apps page opens, the person chooses there)

// (not rodata: i18n.later marks the labels for the catalogue; tr where they are shown)
// Each box is tied to its part: with an install there, it shows what the system has, and what is ticked is what
// Install writes.
@(private = "file")
SETUP_CHOICES := [?]setup.Choice{
	SETUP_PATH        = {label = i18n.later("Feuille in the terminal (on the PATH)"), on = true, parts = {.Path}},
	SETUP_OPEN_PDF    = {label = i18n.later("Open PDF files with Feuille (in Open with)"), on = true, parts = {.Documents}},
	SETUP_DEFAULT_PDF = {label = i18n.later("Feuille opens PDF files by default"), on = false, parts = {.Default_Documents}},
}

// Each frame: the install's dialog and page. The installed copy started takes over once this one ends. (The menu's
// and the session's switches follow the installed copy by themselves: prefs_page.install_follow.)
install_follow :: proc(app: ^App) {
	// (an edited document asks first, as a quit does; the installed copy starts at the end: app_close)
	if prefs_page.install_frame(&app.install) == .Launched { leave_document(app, .Quit) }
}

////////////////////////////////
// The single instance (gt:instance)

// What a second start hands the first: its launcher's activation token on a line of its own, then a line asking the
// install's dialog, then its file. Each mark is a byte no path has.
APP_MESSAGE_TOKEN :: "\x01"
APP_MESSAGE_SETUP :: "\x02"

// The single instance's name: the person's (a debug build has its own: a build tried beside the installed copy).
app_instance_name :: proc() -> string {
	return instance.key(ODIN_DEBUG ? "feuille.dev" : "feuille", platform.user_dir(.Config, "", context.temp_allocator))
}

// Whether a feuille runs and answers (--status: setup.Setup_Options.running).
app_running :: proc() -> bool { return instance.running({name = app_instance_name()}) }

// Asks the feuille that runs to end as its Quit does (--quit: setup.Setup_Options.quit); true when it took the request.
app_quit :: proc() -> bool { return instance.quit({name = app_instance_name()}) }

app_message_make :: proc(token, path: string, setup_asked: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	if token != "" { strings.write_string(&b, APP_MESSAGE_TOKEN); strings.write_string(&b, token); strings.write_byte(&b, '\n') }
	if setup_asked { strings.write_string(&b, APP_MESSAGE_SETUP); strings.write_byte(&b, '\n') }
	strings.write_string(&b, path)
	return strings.to_string(b)
}

app_message_read :: proc(text: string) -> (token, path: string, setup_asked: bool) {
	for line in strings.split_lines(text, context.temp_allocator) {
		switch {
		case strings.has_prefix(line, APP_MESSAGE_TOKEN): token = line[len(APP_MESSAGE_TOKEN):]
		case line == APP_MESSAGE_SETUP:                   setup_asked = true
		case line != "":                                  path = line
		}
	}
	return
}

// A second start's file, or the toolkit's messages (--status, --quit), on the instance's thread: what acts is handed
// to the interface's. (Not private: the tests deliver messages to it.)
app_message :: proc(user: rawptr, message: []byte) {
	app := (^App)(user)
	switch string(message) {
	case instance.MESSAGE_PING: return   // (the answer alone tells --status that feuille runs)
	case instance.MESSAGE_QUIT:
		ui.post(&app.main.state, proc(data: rawptr, _: u64) { leave_document((^App)(data), .Quit) }, app)
		return
	}
	heap := runtime.heap_allocator()
	m := new(App_Message, heap)
	m^ = {app = app, text = strings.clone(string(message), heap)}
	if !ui.post(&app.main.state, app_message_open, m) { app_message_free(m) }
}

@(private = "file")
App_Message :: struct {
	app:  ^App,
	text: string,   // owned (the heap's)
}

@(private = "file")
app_message_free :: proc(m: ^App_Message) {
	heap := runtime.heap_allocator()
	delete(m.text, heap)
	free(m, heap)
}

// The file of a second start opens here (an edited document asks first, as any open does); the window comes to the
// front.
@(private = "file")
app_message_open :: proc(data: rawptr, _: u64) {
	m := (^App_Message)(data)
	defer app_message_free(m)
	app := m.app
	token, path, setup_asked := app_message_read(m.text)
	if path != "" { open_asked(app, path) }
	if setup_asked { prefs_page.install_open(&app.install) }
	platform.raise_window_token(app.main.win, token)
	host.host_settle(&app.main)
}
