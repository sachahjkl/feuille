package feuille

// What starts another program or speaks to the desktop: a page of the site, the document with another application,
// its folder in the file manager, a new feuille, the desktop's list of recent files. Each may wait (a portal asked, a
// process spawned, the system's files read): a task of the pool does it, never the interface's thread, and a failure
// comes back to the status bar. Headless (the tests), nothing starts: what would have is noted in `app.opened`.

import "base:runtime"
import "core:fmt"
import "core:path/filepath"
import "core:strings"
import desktop "gt:desktop"
import host "gt:host"
import i18n "gt:i18n"
import "gt:platform"
import setup "gt:setup"
import tasks "gt:tasks"
import "gt:ui"

Launch_Kind :: enum u8 {
	Url,          // a web page in the browser
	Folder,       // a folder in the file manager
	Open_With,    // the file with the application `id`
	Reveal,       // the file shown in its folder, selected
	New_Window,   // feuille again, with no file
	Recent,       // the file added to the desktop's recent files
}

@(private = "file")
Launch :: struct {
	app:      ^App,
	kind:     Launch_Kind,
	path:     string,   // owned: the file, the folder, the address, or the program
	id:       string,   // owned: Open with's application
	name:     string,   // owned: its name, said when it cannot start
	headless: bool,
}

launch :: proc(app: ^App, kind: Launch_Kind, path: string, id := "", name := "") {
	context.allocator = runtime.heap_allocator()   // (the task frees what it is given: the heap's, whoever calls)
	if app.headless { append(&app.opened, fmt.aprintf("%v:%s", kind, path)) }
	l := new(Launch)
	l^ = {app = app, kind = kind, path = strings.clone(path), id = strings.clone(id), name = strings.clone(name), headless = app.headless}
	if !tasks.add(&app.pool, launch_run, l) { launch_free(l) }
}

@(private = "file")
launch_run :: proc(data: rawptr) {
	l := (^Launch)(data)
	ok := true
	if !l.headless {
		switch l.kind {
		case .Url:        ok = platform.open_url(l.path)
		case .Folder:     ok = platform.open_path(l.path)
		case .Open_With:  ok = desktop.open_with(l.path, l.id)
		case .Reveal:     ok = platform.reveal_in_folder(l.path)
		case .New_Window: ok = setup.launch(l.path)
		case .Recent:     platform.add_recent_file(l.path, "application/pdf")
		}
	}
	if ok || !ui.post(&l.app.main.state, launch_failed, l) { launch_free(l) }
}

// On the interface's thread: why nothing started.
@(private = "file")
launch_failed :: proc(data: rawptr, _: u64) {
	l := (^Launch)(data)
	defer launch_free(l)
	app := l.app
	switch l.kind {
	case .Url:        say(app, i18n.tr("No browser opens %s"), l.path)
	case .Folder:     say(app, i18n.tr("No file manager opens %s"), l.path)
	case .Open_With:  say(app, i18n.tr("%s cannot start"), l.name)
	case .Reveal:     say(app, i18n.tr("%s cannot be shown in its folder"), filepath.base(l.path))
	case .New_Window: say(app, i18n.tr("No window could be started"))
	case .Recent:
	}
	host.host_settle(&app.main)
}

@(private = "file")
launch_free :: proc(l: ^Launch) {
	context.allocator = runtime.heap_allocator()
	delete(l.path)
	delete(l.id)
	delete(l.name)
	free(l)
}

////////////////////////////////
// "Open with": the applications the system knows for a PDF (ui.Open_With: read with their icons on a chore)

// The applications for the document `path`, asked once per document: the menus show them, and keep them until another is.
open_with_ask :: proc(app: ^App, path: string) {
	ow := &app.open_with
	if ow.state != .Idle && ow.path == path { return }
	ui.open_with_ask(ow, &app.main.state, path)
}
