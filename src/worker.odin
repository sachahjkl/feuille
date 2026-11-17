package feuille

// The document's worker: one thread owns the engine and the open document (src/md/infrastructure/pdfium.md). The
// interface's thread leaves asks in the mailbox and pokes the job; the worker posts its answers back (ui.post), each a
// heap value the posted call frees. Nothing here runs on the interface's thread but the asks and worker_stop.

import "base:runtime"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "gt:tasks"
import "gt:ui"
import pdf "pdf"

// A page as the interface knows it: its identity for good, its size in points as shown, its /Rotate in quarter turns.
Snapshot_Page :: struct {
	id:       u64,
	size:     [2]f32,
	rotation: int,
}

// The document's shape after a change (src/md/data/snapshot.md). Immutable once posted; snapshot_free frees it.
Snapshot :: struct {
	revision: u64,
	path:     string,
	pages:    []Snapshot_Page,
}

snapshot_free :: proc(s: ^Snapshot) {
	if s == nil { return }
	delete(s.path)
	delete(s.pages)
	free(s)
}

// A picture to render: a page of a revision, at a size in pixels, with the layer or not.
Render_Ask :: struct {
	revision: u64,
	index:    int,
	id:       u64,
	size:     [2]int,
	layer:    bool,
}

// A rendered page, posted to the interface: its RGBA pixels (size.x * size.y * 4 bytes) are the payload's.
Picture :: struct {
	using ask: Render_Ask,
	rgba:      []u8,
	user:      rawptr,
}

// Why an open failed, posted to the interface.
Open_Failure :: struct {
	path:  string,
	error: pdf.Error,
	user:  rawptr,
}

// What the worker posts, and to whom: the program's procedures, each given its payload (`user` inside it).
Worker_Answers :: struct {
	state:   ^ui.State,
	user:    rawptr,
	opened:  ui.Post_Proc,   // data: ^Opened
	failed:  ui.Post_Proc,   // data: ^Open_Failure
	picture: ui.Post_Proc,   // data: ^Picture
}

Opened :: struct {
	snapshot: ^Snapshot,
	user:     rawptr,
}

Worker :: struct {
	answers:   Worker_Answers,
	pool:      tasks.Pool,
	job:       tasks.Job,
	lock:      sync.Mutex,
	// the mailbox, under `lock`: the newest open, the newest list of renders
	open_asked:    bool,
	open_path:     string,
	open_password: string,
	render_asked:  bool,
	renders:       [dynamic]Render_Ask,
	// the worker's own, on its thread only
	doc:       pdf.Document,
	has_doc:   bool,
	path:      string,
	ids:       [dynamic]u64,
	next_id:   u64,
	revision:  u64,
	allocator: runtime.Allocator,
}

worker_start :: proc(w: ^Worker, answers: Worker_Answers) {
	w.answers = answers
	w.allocator = runtime.heap_allocator()
	w.renders = make([dynamic]Render_Ask, w.allocator)
	w.ids = make([dynamic]u64, w.allocator)
	w.job = {work = worker_run, data = w}
	context.allocator = w.allocator
	tasks.start(&w.pool, {threads = 1})
}

// Stops the thread, then closes the document from here: the engine is ours once the thread is gone.
worker_stop :: proc(w: ^Worker) {
	tasks.stop(&w.pool)
	if w.has_doc {
		pdf.claim()
		pdf.close(&w.doc)
	}
	delete(w.open_path, w.allocator)
	delete(w.open_password, w.allocator)
	delete(w.renders)
	delete(w.ids)
	delete(w.path, w.allocator)
	w^ = {}
}

// Asks to open `path` (password "": none). It replaces an open still waiting.
worker_open :: proc(w: ^Worker, path, password: string) {
	sync.guard(&w.lock)
	delete(w.open_path, w.allocator)
	delete(w.open_password, w.allocator)
	w.open_path = strings.clone(path, w.allocator)
	w.open_password = strings.clone(password, w.allocator)
	w.open_asked = true
	tasks.job_ask(&w.pool, &w.job)
}

// Asks for these pictures, the most wanted first. It replaces the list still waiting.
worker_render :: proc(w: ^Worker, asks: []Render_Ask) {
	sync.guard(&w.lock)
	clear(&w.renders)
	append(&w.renders, ..asks)
	w.render_asked = true
	tasks.job_ask(&w.pool, &w.job)
}

@(private = "file")
worker_run :: proc(data: rawptr) {
	w := (^Worker)(data)
	context.allocator = w.allocator
	found := pdf.init()   // (the engine's thread is this one: init claims it)

	sync.lock(&w.lock)
	open, path, password := w.open_asked, w.open_path, w.open_password
	w.open_asked, w.open_path, w.open_password = false, "", ""
	renders: [dynamic]Render_Ask
	if w.render_asked {
		renders = make([dynamic]Render_Ask, len(w.renders), context.temp_allocator)
		copy(renders[:], w.renders[:])
		w.render_asked = false
	}
	sync.unlock(&w.lock)

	if open {
		defer delete(path)
		defer delete(password)
		if !found { post_failure(w, path, .No_Library) } else { open_now(w, path, password) }
	}
	for r in renders {
		// (a newer list waits: this run ends, and the job runs again on it)
		sync.lock(&w.lock)
		newer := w.render_asked || w.open_asked
		sync.unlock(&w.lock)
		if newer { break }
		render_now(w, r)
	}
}

@(private = "file")
open_now :: proc(w: ^Worker, path, password: string) {
	bytes, read_err := os.read_entire_file_from_path(path, w.allocator)
	if read_err != nil {
		post_failure(w, path, .File)
		return
	}
	doc, err := pdf.open(bytes, password, w.allocator)
	if err != .None {
		delete(bytes, w.allocator)
		post_failure(w, path, err)
		return
	}
	if w.has_doc { pdf.close(&w.doc) }
	w.doc, w.has_doc = doc, true
	delete(w.path, w.allocator)
	w.path = strings.clone(path, w.allocator)
	w.revision += 1
	n := pdf.page_count(doc)
	clear(&w.ids)
	for _ in 0 ..< n {
		w.next_id += 1
		append(&w.ids, w.next_id)
	}
	post_snapshot(w)
}

@(private = "file")
post_snapshot :: proc(w: ^Worker) {
	s := new(Snapshot)
	s.revision = w.revision
	s.path = strings.clone(w.path)
	s.pages = make([]Snapshot_Page, len(w.ids))
	for id, i in w.ids {
		size, _ := pdf.page_size(w.doc, i)
		s.pages[i] = {id = id, size = size, rotation = pdf.page_rotation(w.doc, i)}
	}
	o := new(Opened)
	o^ = {snapshot = s, user = w.answers.user}
	if !ui.post(w.answers.state, w.answers.opened, o) {
		snapshot_free(s)
		free(o)
	}
}

@(private = "file")
post_failure :: proc(w: ^Worker, path: string, err: pdf.Error) {
	f := new(Open_Failure)
	f^ = {path = strings.clone(path), error = err, user = w.answers.user}
	if !ui.post(w.answers.state, w.answers.failed, f) { open_failure_free(f) }
}

open_failure_free :: proc(f: ^Open_Failure) {
	delete(f.path)
	free(f)
}

@(private = "file")
render_now :: proc(w: ^Worker, r: Render_Ask) {
	// (an ask of another revision names pages that may have moved: the interface asks again with the new snapshot)
	if !w.has_doc || r.revision != w.revision || r.index < 0 || r.index >= len(w.ids) || w.ids[r.index] != r.id { return }
	rgba := pdf.render(&w.doc, r.index, r.size.x, r.size.y, r.layer)
	if rgba == nil { return }
	p := new(Picture)
	p^ = {ask = r, rgba = rgba, user = w.answers.user}
	if !ui.post(w.answers.state, w.answers.picture, p) { picture_free(p) }
}

picture_free :: proc(p: ^Picture) {
	delete(p.rgba)
	free(p)
}

// The file's name for a title: its base, or "" for none.
document_name :: proc(path: string) -> string { return filepath.base(path) }
