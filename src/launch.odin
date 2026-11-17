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
// "Open with": the applications the system knows for a PDF

// What the menus show under "Open with": asked of a task for the document open, kept until another is.
Handlers :: struct {
	path:  string,              // owned: the document they were asked for ("": none)
	list:  []desktop.Handler,   // owned (the heap's)
	ready: bool,
}

@(private = "file")
Handlers_Read :: struct {
	app:  ^App,
	path: string,   // owned
	list: []desktop.Handler,
}

// The applications for `path`, asked once per document (the system's associations are files: read on a task).
handlers_ask :: proc(app: ^App, path: string) {
	context.allocator = runtime.heap_allocator()
	h := &app.handlers
	if h.path == path { return }
	handlers_free(h)
	h.path = strings.clone(path)
	// (the tests read none of the person's associations: no application)
	if app.headless { h.ready = true; return }
	job := new(Handlers_Read)
	job^ = {app = app, path = strings.clone(path)}
	work :: proc(data: rawptr) {
		job := (^Handlers_Read)(data)
		job.list = desktop.handlers_for_file(job.path)
		if !ui.post(&job.app.main.state, handlers_done, job) { handlers_read_free(job) }
	}
	if !tasks.add(&app.pool, work, job) { handlers_read_free(job) }
}

@(private = "file")
handlers_done :: proc(data: rawptr, _: u64) {
	job := (^Handlers_Read)(data)
	h := &job.app.handlers
	if h.path == job.path && !h.ready {
		h.list, h.ready = job.list, true
		job.list = nil
		host.host_settle(&job.app.main)
	}
	handlers_read_free(job)
}

@(private = "file")
handlers_read_free :: proc(job: ^Handlers_Read) {
	context.allocator = runtime.heap_allocator()
	if job.list != nil { desktop.handlers_destroy(job.list) }
	delete(job.path)
	free(job)
}

handlers_free :: proc(h: ^Handlers) {
	context.allocator = runtime.heap_allocator()
	if h.list != nil { desktop.handlers_destroy(h.list) }
	delete(h.path)
	h^ = {}
}
