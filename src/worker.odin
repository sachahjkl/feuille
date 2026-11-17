package feuille

// The document's worker: one thread owns the engine and the open document (src/md/infrastructure/pdfium.md). The
// interface's thread leaves asks in the mailbox and pokes the job; the worker posts its answers back (ui.post), each a
// heap value the posted call frees. Nothing here runs on the interface's thread but the asks and worker_stop.
//
// A run takes the whole mailbox, then: the newest open (which drops the edits asked before it: they named the old
// document), the edits in the order they were asked, one snapshot if anything changed, the renders (a newer list or an
// open stops them: the job runs again).

import "base:runtime"
import "core:os"
import "core:strings"
import "core:sync"
import "gt:tasks"
import "gt:ui"
import pdf "pdf"

// A page as the interface knows it: its identity for good, its size in points as shown, its /Rotate in quarter turns,
// and the version of its content (a turn or a text edit moves it: the pictures of another version are stale).
Snapshot_Page :: struct {
	id:       u64,
	size:     [2]f32,
	rotation: int,
	version:  u64,
}

// The document's shape after a change (src/md/data/snapshot.md). Immutable once posted; snapshot_free frees it.
Snapshot :: struct {
	revision: u64,
	opened:   bool,     // a document just opened (not an edit of the one shown)
	path:     string,
	pages:    []Snapshot_Page,
	edited:   bool,     // changed since it was opened or last saved
	can_undo: bool,
	can_redo: bool,
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
	version:  u64,
	size:     [2]int,
	layer:    bool,
	thumb:    bool,   // a thumbnail of the strip (its own cache), not a page of the column
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

// A save or an extract done, or not.
Saved :: struct {
	path:    string,
	ok:      bool,
	extract: bool,
	user:    rawptr,
}

// The block of text under a point, or none (`found` false), for the text edit.
Text_Found :: struct {
	id:     u64,
	found:  bool,
	block:  pdf.Text_Block,   // (its strings the payload's)
	user:   rawptr,
}

// What the worker posts, and to whom: the program's procedures, each given its payload (`user` inside it).
Worker_Answers :: struct {
	state:   ^ui.State,
	user:    rawptr,
	opened:  ui.Post_Proc,   // data: ^Opened
	failed:  ui.Post_Proc,   // data: ^Open_Failure
	picture: ui.Post_Proc,   // data: ^Picture
	saved:   ui.Post_Proc,   // data: ^Saved
	text:    ui.Post_Proc,   // data: ^Text_Found
}

Opened :: struct {
	snapshot: ^Snapshot,
	user:     rawptr,
}

// A hit test of text asked: page `id`, at `at` (shares of the page shown).
Text_Ask :: struct {
	id: u64,
	at: [2]f32,
}

Worker :: struct {
	answers:   Worker_Answers,
	pool:      tasks.Pool,
	job:       tasks.Job,
	lock:      sync.Mutex,
	// the mailbox, under `lock`: the newest open, the edits in order, the newest list of renders, the newest hit test
	open_asked:    bool,
	open_path:     string,
	open_password: string,
	edits_asked:   [dynamic]Edit_Ask,
	render_asked:  bool,
	renders:       [dynamic]Render_Ask,
	text_asked:    bool,
	text_ask:      Text_Ask,
	// the worker's own, on its thread only
	doc:       pdf.Document,
	has_doc:   bool,
	path:      string,
	ids:       [dynamic]u64,
	next_id:   u64,
	revision:  u64,
	edits:     Edits,
	allocator: runtime.Allocator,
}

worker_start :: proc(w: ^Worker, answers: Worker_Answers) {
	w.answers = answers
	w.allocator = runtime.heap_allocator()
	context.allocator = w.allocator
	w.renders = make([dynamic]Render_Ask)
	w.edits_asked = make([dynamic]Edit_Ask)
	w.ids = make([dynamic]u64)
	w.edits.versions = make(map[u64]u64)
	w.job = {work = worker_run, data = w}
	tasks.start(&w.pool, {threads = 1})
}

// Stops the thread, then closes the documents from here: the engine is ours once the thread is gone.
worker_stop :: proc(w: ^Worker) {
	context.allocator = w.allocator
	tasks.stop(&w.pool)
	pdf.claim()
	if w.has_doc { pdf.close(&w.doc) }
	edits_destroy(&w.edits)
	for &a in w.edits_asked { edit_ask_free(&a) }
	delete(w.edits_asked)
	delete(w.open_path)
	delete(w.open_password)
	delete(w.renders)
	delete(w.ids)
	delete(w.path)
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

// Asks for an edit; the worker takes the ask's strings and ids (they must be the worker's allocator's: edit_ask_make).
worker_edit :: proc(w: ^Worker, a: Edit_Ask) {
	sync.guard(&w.lock)
	append(&w.edits_asked, a)
	tasks.job_ask(&w.pool, &w.job)
}

// An edit ask with its strings and ids copied for the worker.
edit_ask_make :: proc(w: ^Worker, kind: Edit_Kind, id: u64 = 0, turns := 0, to := 0, object := 0, text := "", path := "", ids: []u64 = nil) -> Edit_Ask {
	a := Edit_Ask{kind = kind, id = id, turns = turns, to = to, object = object}
	a.text = strings.clone(text, w.allocator)
	a.path = strings.clone(path, w.allocator)
	if ids != nil {
		a.ids = make([]u64, len(ids), w.allocator)
		copy(a.ids, ids)
	}
	return a
}

// Asks for these pictures, the most wanted first. It replaces the list still waiting.
worker_render :: proc(w: ^Worker, asks: []Render_Ask) {
	sync.guard(&w.lock)
	clear(&w.renders)
	append(&w.renders, ..asks)
	w.render_asked = true
	tasks.job_ask(&w.pool, &w.job)
}

// Asks which text block is under `at` of page `id`.
worker_text_at :: proc(w: ^Worker, id: u64, at: [2]f32) {
	sync.guard(&w.lock)
	w.text_ask, w.text_asked = {id, at}, true
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
	edits := make([dynamic]Edit_Ask, len(w.edits_asked), context.temp_allocator)
	copy(edits[:], w.edits_asked[:])
	clear(&w.edits_asked)
	renders: [dynamic]Render_Ask
	if w.render_asked {
		renders = make([dynamic]Render_Ask, len(w.renders), context.temp_allocator)
		copy(renders[:], w.renders[:])
		w.render_asked = false
	}
	text, text_ask := w.text_asked, w.text_ask
	w.text_asked = false
	sync.unlock(&w.lock)

	if open {
		defer delete(path)
		defer delete(password)
		// (the edits asked before it named the document it replaces)
		if !found { post_failure(w, path, .No_Library) } else if open_now(w, path, password) {
			for &a in edits { edit_ask_free(&a) }
			clear(&edits)
		}
	}
	changed := false
	for &a in edits {
		if edit_now(w, &a) { changed = true }
		edit_ask_free(&a)
	}
	if changed {
		w.revision += 1
		post_snapshot(w, false)
	}
	if text { text_now(w, text_ask) }
	for r in renders {
		// (a newer list waits: this run ends, and the job runs again on it)
		sync.lock(&w.lock)
		newer := w.render_asked || w.open_asked || len(w.edits_asked) > 0
		sync.unlock(&w.lock)
		if newer { break }
		render_now(w, r)
	}
}

@(private = "file")
open_now :: proc(w: ^Worker, path, password: string) -> bool {
	bytes, read_err := os.read_entire_file_from_path(path, w.allocator)
	if read_err != nil {
		post_failure(w, path, .File)
		return false
	}
	doc, err := pdf.open(bytes, password, w.allocator)
	if err != .None {
		delete(bytes, w.allocator)
		post_failure(w, path, err)
		return false
	}
	if w.has_doc { pdf.close(&w.doc) }
	edits_reset(&w.edits)
	w.doc, w.has_doc = doc, true
	delete(w.path)
	w.path = strings.clone(path)
	w.revision += 1
	n := pdf.page_count(doc)
	clear(&w.ids)
	for _ in 0 ..< n {
		w.next_id += 1
		append(&w.ids, w.next_id)
	}
	post_snapshot(w, true)
	return true
}

@(private = "file")
post_snapshot :: proc(w: ^Worker, opened: bool) {
	s := new(Snapshot)
	s.revision, s.opened = w.revision, opened
	s.path = strings.clone(w.path)
	s.pages = make([]Snapshot_Page, len(w.ids))
	for id, i in w.ids {
		size, _ := pdf.page_size(w.doc, i)
		s.pages[i] = {id = id, size = size, rotation = pdf.page_rotation(w.doc, i), version = w.edits.versions[id]}
	}
	s.edited = edit_state(&w.edits) != w.edits.saved
	s.can_undo, s.can_redo = len(w.edits.undo) > 0, len(w.edits.redo) > 0
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

post_saved :: proc(w: ^Worker, path: string, ok, extract: bool) {
	s := new(Saved)
	s^ = {path = strings.clone(path), ok = ok, extract = extract, user = w.answers.user}
	if !ui.post(w.answers.state, w.answers.saved, s) { saved_free(s) }
}

saved_free :: proc(s: ^Saved) {
	delete(s.path)
	free(s)
}

@(private = "file")
text_now :: proc(w: ^Worker, a: Text_Ask) {
	if !w.has_doc { return }
	t := new(Text_Found)
	t.id, t.user = a.id, w.answers.user
	for id, i in w.ids {
		if id != a.id { continue }
		t.block, t.found = pdf.text_at(&w.doc, i, a.at)
		break
	}
	if !ui.post(w.answers.state, w.answers.text, t) { text_found_free(t) }
}

text_found_free :: proc(t: ^Text_Found) {
	delete(t.block.text)
	delete(t.block.font)
	free(t)
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
