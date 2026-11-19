package feuille

// The document's worker: one thread holds the list of pages and the files it reads from
// (src/md/infrastructure/engine.md). The interface's thread leaves asks in the mailbox and pokes the job; the worker
// posts its answers back (ui.post), each a heap value the posted call frees. Nothing here runs on the interface's
// thread but the asks and worker_stop.
//
// A run takes the whole mailbox, then: the newest open (which drops the edits asked before it: they named the old
// document), the edits in the order they were asked, one snapshot if anything changed, the renders (a newer list or an
// open stops them: the job runs again).

import "base:runtime"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import pdf "gt:pdf"
import "gt:platform"
import "gt:tasks"
import "gt:ui"

// A stamp as the interface knows it: its place on the page shown (shares of its size: x0, y0, x1, y1), and its style
// and words (the words the snapshot's).
Snapshot_Stamp :: struct {
	box:   [4]f32,
	stamp: pdf.Stamp,
}

// A shape as the interface knows it: its points and its box on the page shown (shares of its size), and its style
// (its points the snapshot's own, as shares).
Snapshot_Shape :: struct {
	box:   [4]f32,
	shape: pdf.Shape,
}

// A page as the interface knows it: its identity for good, its size in points as shown, the quarter turns feuille gave
// it, the version of its content (a turn or a mark moves it: the pictures of another version are stale), its marks.
Snapshot_Page :: struct {
	id:       u64,
	size:     [2]f32,
	rotation: int,
	version:  u64,
	stamps:   []Snapshot_Stamp,
	shapes:   []Snapshot_Shape,
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
	for p in s.pages {
		for st in p.stamps {
			delete(st.stamp.text)
			delete(st.stamp.caption)
		}
		delete(p.stamps)
		for sh in p.shapes { delete(sh.shape.points) }
		delete(p.shapes)
	}
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

// Why an open failed.
Open_Error :: enum u8 {
	None,
	File,         // the file cannot be read
	Format,       // not a PDF, or damaged
	Password,     // a password is needed, or the one given is wrong
	Security,     // an encryption the engine does not know
	Failed,       // the engine failed on it
	Unavailable,  // this build has no engine
}

// Why an open failed, posted to the interface.
Open_Failure :: struct {
	path:  string,
	error: Open_Error,
	user:  rawptr,
}

// A save or an extract done, or not.
Saved :: struct {
	path:    string,
	ok:      bool,
	extract: bool,
	user:    rawptr,
}

// What the worker posts, and to whom: the program's procedures, each given its payload (`user` inside it).
Worker_Answers :: struct {
	state:   ^ui.State,
	user:    rawptr,
	opened:  ui.Post_Proc,   // data: ^Opened
	failed:  ui.Post_Proc,   // data: ^Open_Failure
	picture: ui.Post_Proc,   // data: ^Picture
	saved:   ui.Post_Proc,   // data: ^Saved
	printed: ui.Post_Proc,   // data: ^Printed
	window:  ^platform.Window,   // the owner of the print dialog
}

Opened :: struct {
	snapshot: ^Snapshot,
	user:     rawptr,
}

Worker :: struct {
	answers:   Worker_Answers,
	pool:      tasks.Pool,
	printing:  tasks.Pool,   // a print: its dialog waits for the person, so it never holds the document's thread
	job:       tasks.Job,
	lock:      sync.Mutex,
	// the mailbox, under `lock`: the newest open, the edits in order, the newest list of renders
	open_asked:    bool,
	open_path:     string,
	open_password: string,
	edits_asked:   [dynamic]Edit_Ask,
	render_asked:  bool,
	renders:       [dynamic]Render_Ask,
	// the worker's own, on its thread only
	base:      pdf.Source,          // the file opened
	sources:   [dynamic]pdf.Source, // the files imported since (their pages may come back with an undo)
	has_doc:   bool,
	path:      string,
	pages:     [dynamic]Doc_Page,
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
	w.pages = make([dynamic]Doc_Page)
	w.sources = make([dynamic]pdf.Source)
	w.edits.versions = make(map[u64]u64)
	w.job = {work = worker_run, data = w}
	tasks.start(&w.pool, {threads = 1})
	tasks.start(&w.printing, {threads = 1})
}

// A print's work on the printing thread (print.odin).
print_add :: proc(w: ^Worker, work: proc(data: rawptr), data: rawptr) {
	tasks.add(&w.printing, work, data)
}

// Stops the thread, then lets the document go from here: the list is ours once the thread is gone.
worker_stop :: proc(w: ^Worker) {
	context.allocator = w.allocator
	tasks.stop(&w.pool)
	tasks.stop(&w.printing)   // (a print under way ends first: its pages read the files closed below)
	document_close(w)
	edits_destroy(&w.edits)
	for &a in w.edits_asked { edit_ask_free(&a) }
	delete(w.edits_asked)
	delete(w.open_path)
	delete(w.open_password)
	delete(w.renders)
	delete(w.pages)
	delete(w.sources)
	delete(w.path)
	w^ = {}
}

// The document let go: its pages, their stamps, its edits, its files.
@(private = "file")
document_close :: proc(w: ^Worker) {
	edits_reset(&w.edits)
	for p in w.pages { marks_free(p.page) }
	clear(&w.pages)
	for s in w.sources { pdf.close(s) }
	clear(&w.sources)
	if w.has_doc { pdf.close(w.base) }
	w.base, w.has_doc = 0, false
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
edit_ask_make :: proc(w: ^Worker, kind: Edit_Kind, id: u64 = 0, turns := 0, to := 0, text := "", path := "", ids: []u64 = nil) -> Edit_Ask {
	a := Edit_Ask{kind = kind, id = id, turns = turns, to = to}
	a.text = strings.clone(text, w.allocator)
	a.path = strings.clone(path, w.allocator)
	if ids != nil {
		a.ids = make([]u64, len(ids), w.allocator)
		copy(a.ids, ids)
	}
	return a
}

// A stamp's ask: stamp `index` of page `id` (-1: a new one at `at`) set to `style` with `text` ("": removed); `moved`:
// to `at` (shares of the page shown).
stamp_ask_make :: proc(w: ^Worker, id: u64, index: int, style: pdf.Stamp, text: string, at: [2]f32 = {}, moved := false) -> Edit_Ask {
	a := edit_ask_make(w, .Stamp, id = id, text = text)
	a.index, a.stamp, a.at, a.moved = index, style, at, moved
	// (a signature's caption and effects stay its own: the worker keeps them, and the ask owns no string of the style)
	a.stamp.text, a.stamp.caption = "", ""
	return a
}

// A shape's ask: shape `index` of page `id` (-1: a new one) set to `style` (its kind for a new one); `points` (shares of
// the page shown, copied): its new place, nil to keep it; `remove`: it goes.
shape_ask_make :: proc(w: ^Worker, id: u64, index: int, style: pdf.Shape, points: [][2]f32 = nil, remove := false) -> Edit_Ask {
	a := edit_ask_make(w, .Shape, id = id)
	a.index, a.shape, a.remove = index, style, remove
	a.shape.points = nil
	if points != nil { a.points = slice.clone(points, w.allocator) }
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

@(private = "file")
worker_run :: proc(data: rawptr) {
	w := (^Worker)(data)
	context.allocator = w.allocator

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
	sync.unlock(&w.lock)

	if open {
		defer delete(path)
		defer delete(password)
		// (the edits asked before it named the document it replaces)
		if !pdf.available() { post_failure(w, path, .Unavailable) } else if open_now(w, path, password) {
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
	src, err := pdf.open(bytes, password)
	delete(bytes, w.allocator)   // (the engine keeps its own copy)
	if err != .None {
		post_failure(w, path, open_error(err))
		return false
	}
	document_close(w)
	w.base, w.has_doc = src, true
	delete(w.path)
	w.path = strings.clone(path)
	w.revision += 1
	for i in 0 ..< pdf.page_count(src) {
		w.next_id += 1
		append(&w.pages, Doc_Page{id = w.next_id, page = {source = src, index = i}})
	}
	post_snapshot(w, true)
	return true
}

@(private = "file")
open_error :: proc(e: pdf.Error) -> Open_Error {
	switch e {
	case .None:        return .None
	case .Format:      return .Format
	case .Password:    return .Password
	case .Security:    return .Security
	case .Failed:      return .Failed
	case .Unavailable: return .Unavailable
	}
	return .Failed
}

// A point of the page as its file shows it, in points, on the page shown (turn_back's inverse).
turn_forward :: proc(a: [2]f32, p: pdf.Page, shown: [2]f32) -> [2]f32 {
	k := ((p.turns % 4) + 4) % 4
	size := k % 2 == 1 ? [2]f32{shown.y, shown.x} : shown
	switch k {
	case 1: return {size.y - a.y, a.x}
	case 2: return {size.x - a.x, size.y - a.y}
	case 3: return {a.y, size.x - a.x}
	}
	return a
}

// A stamp's box on the page shown, as shares: its corner turned with the page, its sides with the stamp and the page.
@(private = "file")
stamp_box :: proc(p: pdf.Page, s: pdf.Stamp, shown: [2]f32) -> [4]f32 {
	k := ((p.turns % 4) + 4) % 4
	corner := turn_forward(s.at, p, shown)
	wh := pdf.stamp_size(s)
	lo, hi := corner, corner
	for c in ([4][2]f32{{0, 0}, {wh.x, 0}, {0, wh.y}, wh}) {
		q: [2]f32
		switch (s.turns + k) % 4 {
		case 1: q = {-c.y, c.x}
		case 2: q = {-c.x, -c.y}
		case 3: q = {c.y, -c.x}
		case:   q = c
		}
		lo, hi = {min(lo.x, corner.x + q.x), min(lo.y, corner.y + q.y)}, {max(hi.x, corner.x + q.x), max(hi.y, corner.y + q.y)}
	}
	if shown.x <= 0 || shown.y <= 0 { return {} }
	return {lo.x / shown.x, lo.y / shown.y, hi.x / shown.x, hi.y / shown.y}
}

@(private = "file")
post_snapshot :: proc(w: ^Worker, opened: bool) {
	s := new(Snapshot)
	s.revision, s.opened = w.revision, opened
	s.path = strings.clone(w.path)
	s.pages = make([]Snapshot_Page, len(w.pages))
	for e, i in w.pages {
		shown := pdf.shown_size(e.page)
		sp := Snapshot_Page{id = e.id, size = shown, rotation = e.page.turns, version = w.edits.versions[e.id]}
		if len(e.page.stamps) > 0 {
			sp.stamps = make([]Snapshot_Stamp, len(e.page.stamps))
			for st, k in e.page.stamps {
				sp.stamps[k] = {box = stamp_box(e.page, st, shown), stamp = st}
				sp.stamps[k].stamp.text = strings.clone(st.text)
				sp.stamps[k].stamp.caption = strings.clone(st.caption)
			}
		}
		if len(e.page.shapes) > 0 {
			sp.shapes = make([]Snapshot_Shape, len(e.page.shapes))
			for sh, k in e.page.shapes {
				sp.shapes[k] = {shape = sh}
				sp.shapes[k].shape.points = make([][2]f32, len(sh.points))
				lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
				for q, n in sh.points {
					v := turn_forward(q, e.page, shown) / shown
					sp.shapes[k].shape.points[n] = v
					if math.is_nan(v.x) { continue }   // (between two contours of an outline)
					lo, hi = {min(lo.x, v.x), min(lo.y, v.y)}, {max(hi.x, v.x), max(hi.y, v.y)}
				}
				sp.shapes[k].box = {lo.x, lo.y, hi.x, hi.y}
			}
		}
		s.pages[i] = sp
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
post_failure :: proc(w: ^Worker, path: string, err: Open_Error) {
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
render_now :: proc(w: ^Worker, r: Render_Ask) {
	// (an ask of another revision names pages that may have moved: the interface asks again with the new snapshot)
	if !w.has_doc || r.revision != w.revision || r.index < 0 || r.index >= len(w.pages) || w.pages[r.index].id != r.id { return }
	rgba := pdf.render(w.pages[r.index].page, r.size.x, r.size.y, r.layer)
	if rgba == nil { return }
	p := new(Picture)
	p^ = {ask = r, rgba = rgba, user = w.answers.user}
	if !ui.post(w.answers.state, w.answers.picture, p) { picture_free(p) }
}

picture_free :: proc(p: ^Picture) {
	delete(p.rgba)
	free(p)
}
