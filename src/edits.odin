package feuille

// The document's edits, on the worker (src/md/features/page-edits.md). Each operation, applied, gives back its
// inverse: undo applies the inverse and keeps the inverse's inverse for redo. A removed page waits in a scratch
// document, so that its undo brings back the very page (its content, its annotations), not a copy made later. Pages
// are named by their identity; the worker finds their index when it applies.

import "core:os"
import "core:strings"
import pdf "pdf"

// What the interface asks.
Edit_Kind :: enum u8 {
	Rotate,    // `id` by `turns` quarter turns clockwise (1 or -1)
	Remove,    // the page `id`
	Blank,     // a blank page after `id` (0: at the start), the size of its neighbour
	Import,    // the pages of the PDF at `path`, after `id` (0: at the start)
	Move,      // the page `id` to index `to`
	Text,      // the words of text object `object` of page `id`: `text`
	Undo,
	Redo,
	Save,      // a copy of the document at `path`; it becomes the document's file
	Extract,   // the pages `ids`, in their order, as a new PDF at `path`; the document does not change
}

Edit_Ask :: struct {
	kind:   Edit_Kind,
	id:     u64,
	turns:  int,
	to:     int,
	object: int,
	text:   string,   // owned by the ask
	path:   string,   // owned by the ask
	ids:    []u64,    // owned by the ask
}

edit_ask_free :: proc(a: ^Edit_Ask) {
	delete(a.text)
	delete(a.path)
	delete(a.ids)
	a^ = {}
}

// An operation as the worker applies it. A Batch applies its parts in order; its inverse is theirs in reverse.
Op :: union {
	Op_Rotate,
	Op_Remove,
	Op_Restore,
	Op_Move,
	Op_Text,
	Op_Batch,
}

Op_Rotate  :: struct { id: u64, quarters: int }                // to this rotation
Op_Remove  :: struct { id: u64 }
Op_Restore :: struct { id: u64, scratch: int, at: int }        // the scratch's page `scratch` back at index `at`
Op_Move    :: struct { id: u64, to: int }
Op_Text    :: struct { id: u64, object: int, text: string }    // (text owned)
Op_Batch   :: struct { ops: []Op }                             // (owned)

op_free :: proc(op: ^Op) {
	switch &o in op {
	case Op_Text:  delete(o.text)
	case Op_Batch:
		for &p in o.ops { op_free(&p) }
		delete(o.ops)
	case Op_Rotate, Op_Remove, Op_Restore, Op_Move:
	}
	op^ = nil
}

// An entry of the undo or the redo stack: the operation that goes back, and the state it leaves (edit_state).
Step :: struct {
	op:    Op,
	state: u64,
}

// The edits' part of the worker's state, on its thread only.
Edits :: struct {
	scratch:    pdf.Document,
	has_scratch: bool,
	undo:       [dynamic]Step,
	redo:       [dynamic]Step,
	serial:     u64,   // the last state made
	saved:      u64,   // the state the file holds (0: as opened)
	versions:   map[u64]u64,   // a page's content version, by identity: moves when it turns or its words change
}

edits_reset :: proc(e: ^Edits) {
	for &s in e.undo { op_free(&s.op) }
	for &s in e.redo { op_free(&s.op) }
	clear(&e.undo)
	clear(&e.redo)
	clear(&e.versions)
	if e.has_scratch { pdf.close(&e.scratch) }
	e.has_scratch = false
	e.saved = 0
}

edits_destroy :: proc(e: ^Edits) {
	edits_reset(e)
	delete(e.undo)
	delete(e.redo)
	delete(e.versions)
}

// The state shown: the top of the undo stack's (0: as opened).
edit_state :: proc(e: ^Edits) -> u64 { return len(e.undo) > 0 ? e.undo[len(e.undo) - 1].state : 0 }

@(private = "file")
index_of :: proc(w: ^Worker, id: u64) -> int {
	for v, i in w.ids { if v == id { return i } }
	return -1
}

@(private = "file")
touch :: proc(w: ^Worker, id: u64) { w.edits.versions[id] += 1 }

// Applies `op`; its inverse in `inverse`. ok false: nothing changed.
@(private = "file")
apply :: proc(w: ^Worker, op: Op) -> (inverse: Op, ok: bool) {
	doc := &w.doc
	switch o in op {
	case Op_Rotate:
		i := index_of(w, o.id)
		if i < 0 { return }
		old := pdf.page_rotation(doc^, i)
		if !pdf.set_rotation(doc, i, o.quarters) { return }
		touch(w, o.id)
		return Op_Rotate{o.id, old}, true
	case Op_Remove:
		i := index_of(w, o.id)
		if i < 0 || len(w.ids) <= 1 { return }   // (a PDF keeps one page at least)
		if !w.edits.has_scratch {
			w.edits.scratch, w.edits.has_scratch = pdf.new_document(w.allocator)
			if !w.edits.has_scratch { return }
		}
		at := pdf.page_count(w.edits.scratch)
		if !pdf.import_pages(&w.edits.scratch, doc, {i}, at) { return }
		if !pdf.delete_page(doc, i) { return }
		ordered_remove(&w.ids, i)
		return Op_Restore{o.id, at, i}, true
	case Op_Restore:
		at := clamp(o.at, 0, len(w.ids))
		if !w.edits.has_scratch || !pdf.import_pages(doc, &w.edits.scratch, {o.scratch}, at) { return }
		inject_at(&w.ids, at, o.id)
		return Op_Remove{o.id}, true
	case Op_Move:
		i := index_of(w, o.id)
		to := clamp(o.to, 0, len(w.ids) - 1)
		if i < 0 || i == to || !pdf.move_page(doc, i, to) { return }
		ordered_remove(&w.ids, i)
		inject_at(&w.ids, to, o.id)
		return Op_Move{o.id, i}, true
	case Op_Text:
		i := index_of(w, o.id)
		if i < 0 { return }
		old, read := pdf.object_text_of(doc, i, o.object, w.allocator)
		if !read { return }
		if !pdf.set_text(doc, i, o.object, o.text) {
			delete(old, w.allocator)
			return
		}
		touch(w, o.id)
		return Op_Text{o.id, o.object, old}, true
	case Op_Batch:
		done := make([dynamic]Op, w.allocator)
		for p in o.ops {
			if inv, applied := apply(w, p); applied { append(&done, inv) }
		}
		if len(done) == 0 {
			delete(done)
			return
		}
		// (undone in the reverse order)
		for a, b := 0, len(done) - 1; a < b; a, b = a + 1, b - 1 { done[a], done[b] = done[b], done[a] }
		return Op_Batch{done[:]}, true
	}
	return
}

// A new operation of the person: applied, its inverse on the undo stack, the redo stack forgotten.
@(private = "file")
do_op :: proc(w: ^Worker, op: Op) -> bool {
	op := op
	defer op_free(&op)
	inverse, ok := apply(w, op)
	if !ok { return false }
	e := &w.edits
	for &s in e.redo { op_free(&s.op) }
	clear(&e.redo)
	e.serial += 1
	append(&e.undo, Step{inverse, e.serial})
	return true
}

// Undo or redo: the top of one stack applied, its inverse on the other. The state each stack's entry leaves is the one
// before it was made: the undo stack's entries keep theirs, the redo stack's keep the state they bring back.
@(private = "file")
step :: proc(w: ^Worker, undo: bool) -> bool {
	e := &w.edits
	from := undo ? &e.undo : &e.redo
	to := undo ? &e.redo : &e.undo
	if len(from) == 0 { return false }
	s := pop(from)
	defer op_free(&s.op)
	inverse, ok := apply(w, s.op)
	if !ok { return false }
	// (the state after an undo is the entry below's; a redo brings back the state the entry was made with)
	state := s.state
	append(to, Step{inverse, state})
	return true
}

// Applies one ask of the interface; true when the document changed (a new snapshot is due). A save or an extract says
// its result by `say`.
edit_now :: proc(w: ^Worker, a: ^Edit_Ask) -> (changed: bool) {
	if !w.has_doc { return false }
	switch a.kind {
	case .Rotate:
		i := index_of(w, a.id)
		if i < 0 { return false }
		return do_op(w, Op_Rotate{a.id, pdf.page_rotation(w.doc, i) + a.turns})
	case .Remove:
		return do_op(w, Op_Remove{a.id})
	case .Blank:
		return blank(w, a.id)
	case .Import:
		return import_file(w, a.path, a.id)
	case .Move:
		return do_op(w, Op_Move{a.id, a.to})
	case .Text:
		return do_op(w, Op_Text{a.id, a.object, strings.clone(a.text, w.allocator)})
	case .Undo:
		return step(w, true)
	case .Redo:
		return step(w, false)
	case .Save:
		bytes, ok := pdf.save_copy(w.doc, w.allocator)
		defer delete(bytes, w.allocator)
		written := ok && os.write_entire_file(a.path, bytes) == nil
		if written {
			w.edits.saved = edit_state(&w.edits)
			delete(w.path, w.allocator)
			w.path = strings.clone(a.path, w.allocator)
		}
		post_saved(w, a.path, written, false)
		return written   // (the title and the edit mark follow the new snapshot)
	case .Extract:
		post_saved(w, a.path, extract(w, a.ids, a.path), true)
		return false
	}
	return false
}

// A blank page after `after`, the size of that page (or of the first one).
@(private = "file")
blank :: proc(w: ^Worker, after: u64) -> bool {
	at := 0
	if after != 0 {
		i := index_of(w, after)
		if i < 0 { return false }
		at = i + 1
	}
	size, _ := pdf.page_size(w.doc, max(at - 1, 0))
	if size == {} { size = {595, 842} }
	if !pdf.new_page(&w.doc, at, size) { return false }
	w.next_id += 1
	id := w.next_id
	inject_at(&w.ids, at, id)
	// (its undo removes it; the removal keeps it in the scratch, so a redo brings that very page back)
	e := &w.edits
	for &s in e.redo { op_free(&s.op) }
	clear(&e.redo)
	e.serial += 1
	append(&e.undo, Step{Op_Remove{id}, e.serial})
	return true
}

// The pages of another PDF after `after`: read, inserted, closed; one undo removes them all.
@(private = "file")
import_file :: proc(w: ^Worker, path: string, after: u64) -> bool {
	bytes, err := os.read_entire_file_from_path(path, w.allocator)
	if err != nil { return false }
	src, perr := pdf.open(bytes, "", w.allocator)
	if perr != .None {
		delete(bytes, w.allocator)
		return false
	}
	defer pdf.close(&src)
	at := 0
	if after != 0 {
		i := index_of(w, after)
		if i < 0 { return false }
		at = i + 1
	}
	n := pdf.page_count(src)
	indices := make([]int, n, context.temp_allocator)
	for &v, i in indices { v = i }
	if n == 0 || !pdf.import_pages(&w.doc, &src, indices, at) { return false }
	removes := make([]Op, n, w.allocator)
	for k in 0 ..< n {
		w.next_id += 1
		inject_at(&w.ids, at + k, w.next_id)
		removes[k] = Op_Remove{w.next_id}
	}
	e := &w.edits
	for &s in e.redo { op_free(&s.op) }
	clear(&e.redo)
	e.serial += 1
	append(&e.undo, Step{Op_Batch{removes}, e.serial})
	return true
}

// The pages `ids` as a new PDF at `path`.
@(private = "file")
extract :: proc(w: ^Worker, ids: []u64, path: string) -> bool {
	out, ok := pdf.new_document(w.allocator)
	if !ok { return false }
	defer pdf.close(&out)
	indices := make([dynamic]int, context.temp_allocator)
	for id in ids { if i := index_of(w, id); i >= 0 { append(&indices, i) } }
	if len(indices) == 0 || !pdf.import_pages(&out, &w.doc, indices[:], 0) { return false }
	bytes, saved := pdf.save_copy(out, w.allocator)
	defer delete(bytes, w.allocator)
	return saved && os.write_entire_file(path, bytes) == nil
}
