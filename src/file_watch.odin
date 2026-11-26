package feuille

// The document followed on the disk (src/md/features/file-watch.md): a thread of its own waits on the document's folder
// (fsx.Watch) and compares the file's stamp with the one the worker took when it read the file or wrote it. A new stamp
// comes to the interface's thread, which opens the file again, or says that it changed when it holds edits.

import "base:runtime"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import fsx "gt:fsx"
import host "gt:host"
import i18n "gt:i18n"
import "gt:ui"

Doc_Watch :: struct {
	watch:  fsx.Watch,
	thread: ^thread.Thread,
	app:    ^App,
	mutex:  sync.Mutex,
	path:   string,   // the document followed, the heap's ("": none)
	stamp:  i64,      // its stamp as the worker last read or wrote it
}

@(private = "file")
Doc_Changed :: struct {
	app:  ^App,
	path: string,   // the heap's
}

doc_watch_start :: proc(app: ^App) {
	d := &app.doc_watch
	d.app = app
	d.thread = thread.create_and_start_with_poly_data(d, doc_watch_run)
}

// Ends the waiting thread, then frees the watch. A change on its way finds the window closed and frees itself.
doc_watch_stop :: proc(app: ^App) {
	d := &app.doc_watch
	if d.thread == nil { return }
	fsx.watch_stop(&d.watch)
	thread.join(d.thread)
	thread.destroy(d.thread)
	fsx.watch_close(&d.watch)
	delete(d.path, runtime.heap_allocator())
	d^ = {}
}

// The document now shown and its stamp: its folder is watched from now on. No system call: the waiting thread does them.
doc_watch_follow :: proc(app: ^App, path: string, stamp: i64) {
	d := &app.doc_watch
	heap := runtime.heap_allocator()
	sync.lock(&d.mutex)
	same := d.path == path
	if !same {
		delete(d.path, heap)
		d.path = strings.clone(path, heap)
	}
	d.stamp = stamp
	sync.unlock(&d.mutex)
	if same { return }
	if path == "" { fsx.watch_set(&d.watch, nil); return }
	context.allocator = context.temp_allocator   // (filepath.dir's copy: watch_set keeps its own)
	fsx.watch_set(&d.watch, {filepath.dir(path)})
}

@(private = "file")
doc_watch_run :: proc(d: ^Doc_Watch) {
	if !fsx.watch_open(&d.watch) { return }
	for {
		changed, closed := fsx.watch_wait(&d.watch)
		if closed { break }
		if len(changed) > 0 { doc_watch_check(d) }
		free_all(context.temp_allocator)
	}
}

// After a change in the folder: the document's stamp, and the interface told when it moved.
@(private = "file")
doc_watch_check :: proc(d: ^Doc_Watch) {
	sync.lock(&d.mutex)
	path, stamp := strings.clone(d.path, context.temp_allocator), d.stamp
	sync.unlock(&d.mutex)
	if path == "" { return }
	_, now, ok := fsx.stat(path)
	if !ok || now == stamp { return }
	sync.lock(&d.mutex)
	still := d.path == path
	if still { d.stamp = now }   // (told once: the next change is compared with this one)
	sync.unlock(&d.mutex)
	if !still { return }
	heap := runtime.heap_allocator()
	c := new(Doc_Changed, heap)
	c^ = {app = d.app, path = strings.clone(path, heap)}
	if !ui.post(&d.app.main.state, doc_changed, c) { doc_changed_free(c) }
}

// On the interface's thread: the document's file changed. Opened again when it holds no edits.
@(private = "file")
doc_changed :: proc(data: rawptr, _: u64) {
	c := (^Doc_Changed)(data)
	defer doc_changed_free(c)
	app := c.app
	s := app.snapshot
	if s == nil || s.path != c.path { return }
	name := filepath.base(c.path)
	if s.edited {
		say(app, i18n.tr("%s changed on the disk: your edits stay on the version opened before"), name)
	} else {
		app_open_file(app, c.path, "")
		say(app, i18n.tr("%s changed on the disk and is opened again"), name)
	}
	host.host_settle(&app.main)
}

@(private = "file")
doc_changed_free :: proc(c: ^Doc_Changed) {
	heap := runtime.heap_allocator()
	delete(c.path, heap)
	free(c, heap)
}
