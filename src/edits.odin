package feuille

// The document's edits, on the worker (src/md/features/page-edits.md). The document is a list of pages (gt:pdf's
// Page values over files that never change); each operation, applied, gives back its inverse: undo applies the inverse
// and keeps the inverse's inverse for redo. A removed page's value goes into its inverse, so its undo brings back that
// very page, its turns and its stamps. Pages are named by their identity; the worker finds their index when it applies.

import "core:os"
import "core:strings"
import pdf "gt:pdf"

// What the interface asks.
Edit_Kind :: enum u8 {
	Rotate,    // `id` by `turns` quarter turns clockwise (1 or -1)
	Remove,    // the page `id`
	Blank,     // a blank page after `id` (0: at the start), the size of its neighbour
	Import,    // the pages of the PDF at `path`, after `id` (0: at the start)
	Move,      // the page `id` to index `to`
	Stamp,     // stamp `index` of page `id` (-1: a new one at `at`) set to `stamp`, its words `text` ("": removed);
	           // `moved`: it goes to `at` (shares of the page shown)
	Undo,
	Redo,
	Save,      // a copy of the document at `path`; it becomes the document's file
	Extract,   // the pages `ids`, in their order, as a new PDF at `path`; the document does not change
	Print,     // the document printed (the system's dialog), titled `path`, its layer drawn when `layer`
}

Edit_Ask :: struct {
	kind:   Edit_Kind,
	id:     u64,
	turns:  int,
	to:     int,
	index:  int,
	at:     [2]f32,
	moved:  bool,
	layer:  bool,
	stamp:  pdf.Stamp,   // its style (its text is `text`)
	text:   string,      // owned by the ask
	path:   string,      // owned by the ask
	ids:    []u64,       // owned by the ask
}

edit_ask_free :: proc(a: ^Edit_Ask) {
	delete(a.text)
	delete(a.path)
	delete(a.ids)
	a^ = {}
}

// A page of the list: its identity for good, its value (its stamps and their words owned by the worker).
Doc_Page :: struct {
	id:   u64,
	page: pdf.Page,
}

stamps_clone :: proc(stamps: []pdf.Stamp, allocator := context.allocator) -> []pdf.Stamp {
	if len(stamps) == 0 { return nil }
	out := make([]pdf.Stamp, len(stamps), allocator)
	for s, i in stamps {
		out[i] = s
		out[i].text = strings.clone(s.text, allocator)
	}
	return out
}

stamps_free :: proc(stamps: []pdf.Stamp, allocator := context.allocator) {
	for s in stamps { delete(s.text, allocator) }
	delete(stamps, allocator)
}

// An operation as the worker applies it. A Batch applies its parts in order; its inverse is theirs in reverse. An
// operation that carries a page or stamps owns them until it is applied: then the list owns them.
Op :: union {
	Op_Turn,
	Op_Remove,
	Op_Insert,
	Op_Move,
	Op_Stamps,
	Op_Batch,
}

Op_Turn   :: struct { id: u64, turns: int }               // to these turns
Op_Remove :: struct { id: u64 }
Op_Insert :: struct { entry: Doc_Page, at: int }          // (its stamps owned)
Op_Move   :: struct { id: u64, to: int }
Op_Stamps :: struct { id: u64, stamps: []pdf.Stamp }      // the page's stamps become these (owned)
Op_Batch  :: struct { ops: []Op }                         // (owned)

op_free :: proc(op: ^Op) {
	switch &o in op {
	case Op_Insert: stamps_free(o.entry.page.stamps)
	case Op_Stamps: stamps_free(o.stamps)
	case Op_Batch:
		for &p in o.ops { op_free(&p) }
		delete(o.ops)
	case Op_Turn, Op_Remove, Op_Move:
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
	undo:     [dynamic]Step,
	redo:     [dynamic]Step,
	serial:   u64,   // the last state made
	saved:    u64,   // the state the file holds (0: as opened)
	versions: map[u64]u64,   // a page's content version, by identity: moves when it turns or its stamps change
}

edits_reset :: proc(e: ^Edits) {
	for &s in e.undo { op_free(&s.op) }
	for &s in e.redo { op_free(&s.op) }
	clear(&e.undo)
	clear(&e.redo)
	clear(&e.versions)
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
	for p, i in w.pages { if p.id == id { return i } }
	return -1
}

@(private = "file")
touch :: proc(w: ^Worker, id: u64) { w.edits.versions[id] += 1 }

// Applies `op`, taking what it carries; its inverse in `inverse`. ok false: nothing changed, the op keeps what it owns.
@(private = "file")
apply :: proc(w: ^Worker, op: ^Op) -> (inverse: Op, ok: bool) {
	switch &o in op {
	case Op_Turn:
		i := index_of(w, o.id)
		if i < 0 { return }
		p := &w.pages[i].page
		old := p.turns
		p.turns = ((o.turns % 4) + 4) % 4
		touch(w, o.id)
		return Op_Turn{o.id, old}, true
	case Op_Remove:
		i := index_of(w, o.id)
		if i < 0 || len(w.pages) <= 1 { return }   // (a PDF keeps one page at least)
		entry := w.pages[i]
		ordered_remove(&w.pages, i)
		return Op_Insert{entry, i}, true
	case Op_Insert:
		at := clamp(o.at, 0, len(w.pages))
		inject_at(&w.pages, at, o.entry)
		id := o.entry.id
		o.entry.page.stamps = nil   // (the list owns them now)
		return Op_Remove{id}, true
	case Op_Move:
		i := index_of(w, o.id)
		to := clamp(o.to, 0, len(w.pages) - 1)
		if i < 0 || i == to { return }
		entry := w.pages[i]
		ordered_remove(&w.pages, i)
		inject_at(&w.pages, to, entry)
		return Op_Move{o.id, i}, true
	case Op_Stamps:
		i := index_of(w, o.id)
		if i < 0 { return }
		p := &w.pages[i].page
		old := p.stamps
		p.stamps, o.stamps = o.stamps, nil
		touch(w, o.id)
		return Op_Stamps{o.id, old}, true
	case Op_Batch:
		done := make([dynamic]Op, w.allocator)
		for &p in o.ops {
			if inv, applied := apply(w, &p); applied { append(&done, inv) }
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
	inverse, ok := apply(w, &op)
	if !ok { return false }
	push_undo(w, inverse)
	return true
}

@(private = "file")
push_undo :: proc(w: ^Worker, inverse: Op) {
	e := &w.edits
	for &s in e.redo { op_free(&s.op) }
	clear(&e.redo)
	e.serial += 1
	append(&e.undo, Step{inverse, e.serial})
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
	inverse, ok := apply(w, &s.op)
	if !ok { return false }
	append(to, Step{inverse, s.state})
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
		return do_op(w, Op_Turn{a.id, w.pages[i].page.turns + a.turns})
	case .Remove:
		return do_op(w, Op_Remove{a.id})
	case .Blank:
		return blank(w, a.id)
	case .Import:
		return import_file(w, a.path, a.id)
	case .Move:
		return do_op(w, Op_Move{a.id, a.to})
	case .Stamp:
		return stamp(w, a)
	case .Undo:
		return step(w, true)
	case .Redo:
		return step(w, false)
	case .Save:
		bytes, ok := pdf.write(list_of(w, nil), w.base, w.allocator)
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
		bytes, ok := pdf.write(list_of(w, a.ids), 0, w.allocator)
		defer delete(bytes, w.allocator)
		post_saved(w, a.path, ok && os.write_entire_file(a.path, bytes) == nil, true)
		return false
	case .Print:
		print_start(w, a.path, a.layer)
		return false
	}
	return false
}

// A copy of the document's pages, their stamps with them, for a thread that outlives this run (printing).
pages_clone :: proc(w: ^Worker, allocator := context.allocator) -> []pdf.Page {
	out := make([]pdf.Page, len(w.pages), allocator)
	for p, i in w.pages {
		out[i] = p.page
		out[i].stamps = stamps_clone(p.page.stamps, allocator)
	}
	return out
}

// The pages' values, in order (`ids`: those pages only, in their order), in temporary memory.
@(private = "file")
list_of :: proc(w: ^Worker, ids: []u64) -> []pdf.Page {
	out := make([dynamic]pdf.Page, context.temp_allocator)
	if ids == nil {
		for p in w.pages { append(&out, p.page) }
	} else {
		for id in ids { if i := index_of(w, id); i >= 0 { append(&out, w.pages[i].page) } }
	}
	return out[:]
}

@(private = "file")
new_id :: proc(w: ^Worker) -> u64 {
	w.next_id += 1
	return w.next_id
}

// A blank page after `after`, the size of that page as shown (or of the first one).
@(private = "file")
blank :: proc(w: ^Worker, after: u64) -> bool {
	at := 0
	if after != 0 {
		i := index_of(w, after)
		if i < 0 { return false }
		at = i + 1
	}
	size := pdf.shown_size(w.pages[max(at - 1, 0)].page)
	if size.x <= 0 || size.y <= 0 { size = {595, 842} }
	return do_op(w, Op_Insert{Doc_Page{id = new_id(w), page = {size = size}}, at})
}

// The pages of another PDF after `after`: opened as a source that stays open with the document; one undo removes them.
@(private = "file")
import_file :: proc(w: ^Worker, path: string, after: u64) -> bool {
	at := 0
	if after != 0 {
		i := index_of(w, after)
		if i < 0 { return false }
		at = i + 1
	}
	bytes, err := os.read_entire_file_from_path(path, w.allocator)
	if err != nil { return false }
	src, perr := pdf.open(bytes)
	delete(bytes, w.allocator)   // (the engine keeps its own copy)
	if perr != .None { return false }
	n := pdf.page_count(src)
	if n == 0 {
		pdf.close(src)
		return false
	}
	append(&w.sources, src)
	removes := make([]Op, n, w.allocator)
	for k in 0 ..< n {
		entry := Doc_Page{id = new_id(w), page = {source = src, index = k}}
		inject_at(&w.pages, at + k, entry)
		removes[k] = Op_Remove{entry.id}
	}
	push_undo(w, Op_Batch{removes})
	return true
}

// The point `at` (shares of a page shown with `turns`, `shown` its size) in the page as its file shows it (`size`).
turn_back :: proc(at: [2]f32, shown, size: [2]f32, turns: int) -> [2]f32 {
	p := at * shown
	switch ((turns % 4) + 4) % 4 {
	case 1: return {p.y, size.y - p.x}
	case 2: return {size.x - p.x, size.y - p.y}
	case 3: return {size.x - p.y, p.x}
	}
	return p
}

// The stamps of page `id` after the ask: a new one, one changed, one moved, or one removed (its words empty).
@(private = "file")
stamp :: proc(w: ^Worker, a: ^Edit_Ask) -> bool {
	i := index_of(w, a.id)
	if i < 0 { return false }
	p := w.pages[i].page
	shown := pdf.shown_size(p)
	size := ((p.turns % 4) + 4) % 4 % 2 == 1 ? [2]f32{shown.y, shown.x} : shown
	list := make([dynamic]pdf.Stamp, w.allocator)
	for s in p.stamps { append(&list, s) }
	defer delete(list)
	s := a.stamp
	s.text = a.text
	switch {
	case a.index < 0:
		if a.text == "" { return false }
		s.at = turn_back(a.at, shown, size, p.turns)
		s.turns = (4 - (((p.turns % 4) + 4) % 4)) % 4
		append(&list, s)
	case a.index < len(list):
		if a.text == "" {
			ordered_remove(&list, a.index)
		} else {
			old := list[a.index]
			s.at, s.turns = old.at, old.turns
			// (moved: upright where it lands, so its corner is the point given)
			if a.moved {
				s.at = turn_back(a.at, shown, size, p.turns)
				s.turns = (4 - (((p.turns % 4) + 4) % 4)) % 4
			}
			list[a.index] = s
		}
	case:
		return false
	}
	return do_op(w, Op_Stamps{a.id, stamps_clone(list[:], w.allocator)})
}
