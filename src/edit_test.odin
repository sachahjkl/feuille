package feuille

// The edits in the window, end to end: the keys, the worker, the snapshot that comes back, undo and redo, the saved
// copy, text put on a page, a thumbnail dragged, the question before edits are lost.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import pdf "gt:pdf"
import "gt:testkit"
import session "gt:testkit/session"
import "gt:ui"

// Pages told apart by their widths.
@(private = "file")
three_pages :: proc(t: ^testing.T) -> string {
	return write_pdf(t, "three.pdf", {pages = {{size = {200, 280}}, {size = {210, 280}}, {size = {220, 280}}}})
}

@(private = "file")
widths :: proc(app: ^App) -> []f32 {
	out := make([]f32, len(app.snapshot.pages), context.temp_allocator)
	for p, i in app.snapshot.pages { out[i] = p.size.x }
	return out
}

@(private = "file")
expect_widths :: proc(t: ^testing.T, app: ^App, want: []f32, loc := #caller_location) {
	got := widths(app)
	testing.expectf(t, slice.equal(got, want), "the pages' widths are %v, not %v", got, want, loc = loc)
}

@(private = "file")
Revision :: struct { app: ^App, after: u64 }

// Waits for the snapshot after the one of `before`.
@(private = "file")
next_snapshot :: proc(s: ^session.Session, app: ^App, before: u64, what: string, loc := #caller_location) {
	session.wait_until(s, Revision{app, before}, proc(s: ^session.Session, r: Revision) -> bool {
		return r.app.snapshot != nil && r.app.snapshot.revision > r.after && pictures_ready(s, r.app)
	}, what, loc = loc)
}

@(test)
pages_are_turned_removed_and_brought_back :: proc(t: ^testing.T) {
	s, app := start(t, three_pages(t))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	testing.expect_value(t, app.selected, app.snapshot.pages[0].id)

	// the second page selected by its thumbnail, then turned
	session.click(s, fmt.tprintf("thumb%d", app.snapshot.pages[1].id))
	testing.expect_value(t, app.selected, app.snapshot.pages[1].id)
	rev := app.snapshot.revision
	session.key(s, .R, {.Ctrl})
	next_snapshot(s, app, rev, "the page turned")
	testing.expect_value(t, app.snapshot.pages[1].rotation, 1)
	testing.expect_value(t, app.snapshot.pages[1].size, [2]f32{280, 210})
	testing.expect(t, app.snapshot.edited && app.snapshot.can_undo, "edited, and it can be undone")

	// removed: the next page is selected; undone: the very page is back, selected
	id := app.selected
	rev = app.snapshot.revision
	session.key(s, .Delete)
	next_snapshot(s, app, rev, "the page removed")
	testing.expect_value(t, len(app.snapshot.pages), 2)
	testing.expect_value(t, app.selected, app.snapshot.pages[1].id)
	rev = app.snapshot.revision
	session.key(s, .Z, {.Ctrl})
	next_snapshot(s, app, rev, "the removal undone")
	testing.expect_value(t, len(app.snapshot.pages), 3)
	testing.expect_value(t, app.snapshot.pages[1].id, id)
	testing.expect_value(t, app.snapshot.pages[1].rotation, 1)

	// redo removes it again; two undos bring back the document as opened
	rev = app.snapshot.revision
	session.key(s, .Z, {.Ctrl, .Shift})
	next_snapshot(s, app, rev, "the removal redone")
	testing.expect_value(t, len(app.snapshot.pages), 2)
	for _ in 0 ..< 2 {
		rev = app.snapshot.revision
		session.key(s, .Z, {.Ctrl})
		next_snapshot(s, app, rev, "an undo")
	}
	expect_widths(t, app, {200, 210, 220})
	testing.expect_value(t, app.snapshot.pages[1].rotation, 0)
	testing.expect(t, !app.snapshot.edited, "back as opened: not edited")
}

@(test)
a_blank_page_and_a_move_then_a_saved_copy :: proc(t: ^testing.T) {
	s, app := start(t, three_pages(t))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	rev := app.snapshot.revision
	session.key(s, .N, {.Ctrl, .Shift})   // a blank page after the first
	next_snapshot(s, app, rev, "a blank page added")
	expect_widths(t, app, {200, 200, 210, 220})
	rev = app.snapshot.revision
	session.key(s, .Down, {.Alt})   // the first page down one
	next_snapshot(s, app, rev, "the page moved")
	testing.expect_value(t, app.selected_at, 1)

	dir := testkit.temp_folder(t, "feuille-save")
	path := fmt.tprintf("%s/copy.pdf", dir)
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Save, path = path))
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.snapshot != nil && !app.snapshot.edited }, "saved: not edited any more")
	testing.expect(t, os.exists(path), "the copy is written")
	testing.expect_value(t, app.snapshot.path, path)

	// the copy opened again holds the edits
	app_open_file(app, path, "")
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.snapshot.opened && pictures_ready(s, app) }, "the copy opens")
	testing.expect_value(t, len(app.snapshot.pages), 4)
}

@(test)
a_dragged_thumbnail_moves_its_page :: proc(t: ^testing.T) {
	s, app := start(t, three_pages(t))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	first := session.get(s, fmt.tprintf("thumb%d", app.snapshot.pages[0].id))
	last := session.get(s, fmt.tprintf("thumb%d", app.snapshot.pages[2].id))
	k := app.main.state.scale
	from := session.center(first)
	to := [2]f32{from.x, (last.rect.max.y - 2) * k}
	rev := app.snapshot.revision
	session.drag(s, from, to)
	next_snapshot(s, app, rev, "the page moved by its thumbnail")
	expect_widths(t, app, {210, 220, 200})
}

// The text tool: a click places a stamp, Enter puts it on the page (its box comes back in the snapshot, where it was
// clicked), a click on it opens it again with its words, and the saved copy holds it.
@(test)
text_is_put_on_a_page_and_saved :: proc(t: ^testing.T) {
	s, app := start(t, three_pages(t))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	page := session.get(s, fmt.tprintf("page%d", app.snapshot.pages[0].id))
	k := app.main.state.scale
	w, h := page.rect.max.x - page.rect.min.x, page.rect.max.y - page.rect.min.y
	at := [2]f32{(page.rect.min.x + 0.25 * w) * k, (page.rect.min.y + 0.3 * h) * k}
	session.key(s, .T)
	testing.expect(t, app.tool == .Text, "T turns the text tool on")
	app.style.background = {0, 0, 0, 255}
	session.click_at(s, at)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.text.open }, "the field opens where it was clicked")
	session.type_text(s, "Paid")
	rev := app.snapshot.revision
	session.key(s, .Return)
	next_snapshot(s, app, rev, "the text put on the page")
	stamps := app.snapshot.pages[0].stamps
	testing.expect_value(t, len(stamps), 1)
	testing.expect_value(t, stamps[0].stamp.text, "Paid")
	b := stamps[0].box
	testing.expectf(t, abs(b[0] - 0.25) < 0.01 && abs(b[1] - 0.3) < 0.01 && b[2] > b[0] && b[3] > b[1], "its box starts where it was clicked (%v)", b)
	testing.expect(t, app.snapshot.edited && app.snapshot.pages[0].version == 1, "edited, the page drawn again")

	// a click on it opens it with its words; new words replace them
	session.click_at(s, at + {2, 2} * k)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.text.open }, "the field opens on the text")
	testing.expect_value(t, app.text.before, "Paid")
	session.key(s, .A, {.Ctrl})
	session.type_text(s, "Paid in full")
	rev = app.snapshot.revision
	session.key(s, .Return)
	next_snapshot(s, app, rev, "the words changed")
	testing.expect_value(t, app.snapshot.pages[0].stamps[0].stamp.text, "Paid in full")

	// saved, opened again: the text is part of the page
	dir := testkit.temp_folder(t, "feuille-stamp")
	path := fmt.tprintf("%s/stamped.pdf", dir)
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Save, path = path))
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.snapshot != nil && !app.snapshot.edited }, "saved")
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	testing.expect(t, err == nil && strings.contains(string(data), "Paid in full"), "the saved copy holds the words")
	// (the text clicked is the chosen mark: Escape lets it go first, then leaves the tool)
	session.key(s, .Escape)
	testing.expect(t, app.chosen.kind == .None && app.tool == .Text, "Escape lets the chosen text go")
	session.key(s, .Escape)
	testing.expect(t, app.tool == .None, "Escape again leaves the tool")
}

// The shape tools and moving a mark, with the pointer: a rectangle drawn by a drag, then dragged elsewhere; a text put,
// then dragged; Delete takes the chosen mark and leaves its page; the saved copy holds the marks.
@(test)
shapes_are_drawn_and_marks_are_moved :: proc(t: ^testing.T) {
	s, app := start(t, three_pages(t))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	page := session.get(s, fmt.tprintf("page%d", app.snapshot.pages[0].id))
	k := app.main.state.scale
	w, h := page.rect.max.x - page.rect.min.x, page.rect.max.y - page.rect.min.y
	px :: proc(page: ^ui.Box, w, h, k: f32, x, y: f32) -> [2]f32 { return {(page.rect.min.x + x * w) * k, (page.rect.min.y + y * h) * k} }

	// a rectangle, from (0.2, 0.2) to (0.5, 0.4)
	session.key(s, .R)
	testing.expect(t, app.tool == .Rect, "R: the rectangle")
	rev := app.snapshot.revision
	session.drag(s, px(page, w, h, k, 0.2, 0.2), px(page, w, h, k, 0.5, 0.4))
	next_snapshot(s, app, rev, "the rectangle drawn")
	shapes := app.snapshot.pages[0].shapes
	testing.expect_value(t, len(shapes), 1)
	b := shapes[0].box
	testing.expectf(t, abs(b[0] - 0.2) < 0.02 && abs(b[1] - 0.2) < 0.02 && abs(b[2] - 0.5) < 0.02 && abs(b[3] - 0.4) < 0.02, "where it was drawn (%v)", b)
	testing.expect_value(t, shapes[0].shape.kind, pdf.Shape_Kind.Rect)

	// dragged by its edge, 0.2 to the right
	rev = app.snapshot.revision
	session.drag(s, px(page, w, h, k, 0.2, 0.3), px(page, w, h, k, 0.4, 0.3))
	next_snapshot(s, app, rev, "the rectangle moved")
	b = app.snapshot.pages[0].shapes[0].box
	testing.expectf(t, abs(b[0] - 0.4) < 0.02 && abs(b[2] - 0.7) < 0.02, "moved right (%v)", b)

	// a text, then dragged down
	session.key(s, .T)
	session.click_at(s, px(page, w, h, k, 0.1, 0.7))
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.text.open }, "the field opens")
	session.type_text(s, "Moved")
	rev = app.snapshot.revision
	session.key(s, .Return)
	next_snapshot(s, app, rev, "the text put")
	rev = app.snapshot.revision
	session.drag(s, px(page, w, h, k, 0.11, 0.71), px(page, w, h, k, 0.11, 0.81))
	next_snapshot(s, app, rev, "the text moved")
	tb := app.snapshot.pages[0].stamps[0].box
	testing.expectf(t, abs(tb[1] - 0.8) < 0.02, "the text went down (%v)", tb)
	testing.expect(t, !app.text.open, "a drag moves the text, it does not open it")

	// Delete: the chosen mark goes, the page stays
	testing.expect(t, app.chosen.kind == .Stamp, "the dragged text is the chosen mark")
	rev = app.snapshot.revision
	session.key(s, .Delete)
	next_snapshot(s, app, rev, "the text removed")
	testing.expect_value(t, len(app.snapshot.pages), 3)
	testing.expect_value(t, len(app.snapshot.pages[0].stamps), 0)
	testing.expect_value(t, len(app.snapshot.pages[0].shapes), 1)

	// saved: the rectangle is in the page's content
	path := fmt.tprintf("%s/drawn.pdf", testkit.temp_folder(t, "feuille-shapes"))
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Save, path = path))
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.snapshot != nil && !app.snapshot.edited }, "saved")
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	testing.expect(t, err == nil && strings.contains(string(data), " re"), "the saved page draws the rectangle")
}

@(test)
edits_are_not_lost_without_a_question :: proc(t: ^testing.T) {
	s, app := start(t, three_pages(t))
	session.wait_until(s, app, pictures_ready, "the document is drawn")
	rev := app.snapshot.revision
	session.key(s, .R, {.Ctrl})
	next_snapshot(s, app, rev, "the page turned")
	session.key(s, .Q, {.Ctrl})
	session.wait_text(s, "Leave the edits unsaved?")
	testing.expect(t, !app.quit, "the program waits for the answer")
	session.key(s, .Escape)
	session.frames(s, 3)
	testing.expect(t, !app.quit, "cancelled: it stays")
}
