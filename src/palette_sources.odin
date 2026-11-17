package feuille

// feuille's own sources of the command palette: `@` the pages of the document ("Page 3 of 12"), `/` the recent PDFs
// (recent.odin). The commands and the settings are the toolkit's sources (actions.odin). Both answer at once, from
// what the interface holds: no file is read.

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "core:strings"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:ui"

Palette_Sources :: struct {
	pages:         ui.Palette_Source,
	recent:        ui.Palette_Source,
	pages_for:     u64,   // the snapshot's revision the pages source last answered for
	recent_for:    u64,   // the memory's version the recent source last answered for
}

// Once, with the palette (palette_init).
palette_sources_add :: proc(app: ^App) {
	ps := &app.palette_state.sources
	ps.pages = {
		name = "page", title = i18n.later("Pages"), prefix = .Go_To, searches = true, enter = i18n.later("Show"),
		read = pages_read, mark = pages_mark, poll = pages_poll, act = pages_act, user = app,
	}
	ps.recent = {
		name = "recent", title = i18n.later("Recent PDFs"), prefix = .Paths, plain = true, enter = i18n.later("Open"),
		read = recent_read, poll = recent_poll, act = recent_act, user = app,
	}
	ui.palette_add(&app.palette, &ps.pages)
	ui.palette_add(&app.palette, &ps.recent)
}

// The palette opened on a source: `@` the pages, `/` the recent PDFs.
palette_open_on :: proc(app: ^App, prefix: ui.Palette_Prefix) {
	ui.palette_open(&app.palette, fmt.tprintf("%c", ui.palette_prefix_char(prefix)))
}

////////////////////////////////
// `@` The pages

// Every page, or the one a number names. Made at once from the snapshot: a list of the page count, made when the
// palette asks (its version moves with the document), never in a frame.
@(private = "file")
pages_read :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source, q: ui.Palette_Question) {
	app := (^App)(src.user)
	a: ui.Palette_Answer
	al := ui.palette_answer_allocator(&a)
	s := app.snapshot
	n := s != nil ? len(s.pages) : 0
	items := make([dynamic]ui.Palette_Item, al)
	item :: proc(items: ^[dynamic]ui.Palette_Item, i, n: int, al: runtime.Allocator) {
		append(items, ui.Palette_Item{
			id = fmt.aprintf("%d", i, allocator = al), title = fmt.aprintf(i18n.tr("Page %d of %d"), i + 1, n, allocator = al),
			icon = lucide.FILE_TEXT,
		})
	}
	// (a number: its page alone; else every page, the palette's search ranks them)
	if k, ok := strconv.parse_int(strings.trim_space(q.query)); ok {
		if k >= 1 && k <= n { item(&items, k - 1, n, al) }
	} else {
		for i in 0 ..< n { item(&items, i, n, al) }
	}
	a.items = items[:]
	ui.palette_answer(q, &a)
}

// The page in the middle of the view.
@(private = "file")
pages_mark :: proc(src: ^ui.Palette_Source, id: string) -> bool {
	app := (^App)(src.user)
	n, ok := strconv.parse_int(id)
	return ok && n == app.current
}

@(private = "file")
pages_poll :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source) {
	app := (^App)(src.user)
	ps := &app.palette_state.sources
	rev := app.snapshot != nil ? app.snapshot.revision : 0
	if rev != ps.pages_for {
		ps.pages_for = rev
		src.version += 1
	}
}

@(private = "file")
pages_act :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source, c: ui.Palette_Choice) {
	app := (^App)(src.user)
	if n, ok := strconv.parse_int(c.id); ok { go_to_page(app, n) }
}

////////////////////////////////
// `/` The recent PDFs

// The list as the memory holds it (the document shown is its first: an open puts it there).
@(private = "file")
recent_read :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source, q: ui.Palette_Question) {
	app := (^App)(src.user)
	a: ui.Palette_Answer
	al := ui.palette_answer_allocator(&a)
	items := make([dynamic]ui.Palette_Item, al)
	for path in app.memory.recent {
		name, folder := recent_label(path)
		append(&items, ui.palette_item_clone({id = path, title = name, detail = folder, icon = lucide.FILE_TEXT}, al))
	}
	a.items = items[:]
	ui.palette_answer(q, &a)
}

@(private = "file")
recent_poll :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source) {
	app := (^App)(src.user)
	ps := &app.palette_state.sources
	if app.memory.version != ps.recent_for {
		ps.recent_for = app.memory.version
		src.version += 1
	}
}

// A recent PDF chosen: it opens (an edited document asks first).
@(private = "file")
recent_act :: proc(p: ^ui.Command_Palette, src: ^ui.Palette_Source, c: ui.Palette_Choice) {
	open_asked((^App)(src.user), c.id)
}
