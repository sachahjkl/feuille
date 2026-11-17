package feuille

// The documents feuille remembers (src/md/features/memory.md): the recent PDFs, the most recent first, each with the
// page it showed last; and each one's zoom (the toolkit's Zoom_Memory, by the document's path: the pages' zone has it
// as its key). Two small files of the state folder (gt:store), read once at the start before the window is shown, and
// written by their stores' workers: a frame reads and changes them in memory only. The list holds RECENT_KEPT
// documents; a document that leaves it leaves its zoom too, so neither file grows without end.

import "base:runtime"
import "core:fmt"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import store "gt:store"
import "gt:platform"
import "gt:ui"

// The documents the list keeps.
RECENT_KEPT :: 30

// The stores and what the view reads of them.
Memory :: struct {
	documents: store.Store,         // path -> the page shown last (an index), the most recent first
	zooms:     store.Store,         // path -> its zoom (the zone's memory writes it)
	zoom:      ui.Zoom_Memory,
	recent:    [dynamic]string,     // the documents' paths, as `documents` orders them (owned)
	version:   u64,                 // moves with `recent` (the palette's source reads it again)
	page_kept: int,                 // the page last written for the document shown (-1: none)
}

documents_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/documents.txt"}, allocator)
}

zooms_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/zooms.txt"}, allocator)
}

// The files read (headless: none, the memory lives for the run). At the start, before the window shows.
memory_open :: proc(app: ^App) {
	m := &app.memory
	m.page_kept = -1
	store.open(&m.documents, app.headless ? "" : documents_path())
	store.open(&m.zooms, app.headless ? "" : zooms_path())
	ui.zoom_memory_load(&m.zoom, &m.zooms)
	app.zone.memory = &m.zoom
	recent_mirror(app)
}

// What is left to write is written (the stores' workers end).
memory_close :: proc(app: ^App) {
	m := &app.memory
	app.zone.memory = nil
	ui.zoom_memory_destroy(&m.zoom)
	store.close(&m.zooms)
	store.close(&m.documents)
	for p in m.recent { delete(p) }
	delete(m.recent)
}

// `path` first of the list, its page kept; one past RECENT_KEPT leaves with its zoom. The desktop's list of recent
// files has it too (a task).
recent_add :: proc(app: ^App, path: string) {
	m := &app.memory
	page, _ := store.get(&m.documents, path)
	entries := make([dynamic]store.Entry, 0, RECENT_KEPT, context.temp_allocator)
	append(&entries, store.Entry{path, page != "" ? page : "0"})
	for e in store.list(&m.documents) {
		if e.key == path { continue }
		if len(entries) < RECENT_KEPT { append(&entries, e) } else { ui.zoom_memory_forget(&m.zoom, e.key) }
	}
	store.replace(&m.documents, entries[:])
	recent_mirror(app)
	launch(app, .Recent, path)
}

// `path` off the list (a file that is gone), with its zoom.
recent_forget :: proc(app: ^App, path: string) {
	m := &app.memory
	store.remove(&m.documents, path)
	ui.zoom_memory_forget(&m.zoom, path)
	recent_mirror(app)
}

// The page `path` showed last (0: none kept).
recent_page :: proc(app: ^App, path: string) -> int {
	text, ok := store.get(&app.memory.documents, path)
	if !ok { return 0 }
	n, _ := strconv.parse_int(text)
	return max(n, 0)
}

// The page shown now kept for the document: when it changed (one line in memory; the store's worker writes it).
recent_page_keep :: proc(app: ^App) {
	m := &app.memory
	s := app.snapshot
	if s == nil || app.current == m.page_kept { return }
	m.page_kept = app.current
	if _, known := store.get(&m.documents, s.path); known { store.set(&m.documents, s.path, fmt.tprintf("%d", app.current)) }
}

// The list the palette and the start read, copied from the store.
@(private = "file")
recent_mirror :: proc(app: ^App) {
	context.allocator = runtime.heap_allocator()   // (the App's, whoever calls: a build, a worker's answer)
	m := &app.memory
	for p in m.recent { delete(p) }
	clear(&m.recent)
	for k in store.keys(&m.documents) { append(&m.recent, strings.clone(k)) }
	m.version += 1
}

// A recent document's name and its folder, as the palette shows them.
recent_label :: proc(path: string) -> (name, folder: string) {
	return filepath.base(path), filepath.dir(path)
}
