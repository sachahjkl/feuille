package feuille

// The edits in the window, end to end: the keys, the worker, the snapshot that comes back, undo and redo, the saved
// copy, the text of a block, a thumbnail dragged, the question before edits are lost.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:testing"
import "gt:testkit"
import session "gt:testkit/session"
import fixture "fixture"

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

@(test)
a_text_block_is_changed_in_place :: proc(t: ^testing.T) {
	dir := testkit.temp_folder(t, "feuille-text")
	path := fmt.tprintf("%s/form.pdf", dir)
	testing.expect(t, os.write_entire_file(path, fixture.make_sample(context.temp_allocator)) == nil)
	s, app := start(t, path)
	session.wait_until(s, app, pictures_ready, "the form is drawn")
	page := session.get(s, fmt.tprintf("page%d", app.snapshot.pages[0].id))
	k := app.main.state.scale
	w, h := page.rect.max.x - page.rect.min.x, page.rect.max.y - page.rect.min.y
	// "Full name", at (64, 624) on a page of 595 x 842 points
	at := [2]f32{(page.rect.min.x + (64 + 12) / 595.0 * w) * k, (page.rect.min.y + (1 - (624 + 3) / 842.0) * h) * k}
	session.click_at(s, at, count = 2)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.text.open }, "the field opens over the block")
	testing.expect_value(t, app.text.before, "Full name")
	session.key(s, .A, {.Ctrl})
	session.type_text(s, "Nom complet")
	rev := app.snapshot.revision
	session.key(s, .Return)
	next_snapshot(s, app, rev, "the words changed")
	testing.expect(t, app.snapshot.edited, "edited")
	testing.expect_value(t, app.snapshot.pages[0].version, 1)

	// the same place again reads the new words
	session.click_at(s, at, count = 2)
	session.wait_until(s, app, proc(s: ^session.Session, app: ^App) -> bool { return app.text.open }, "the field opens again")
	testing.expect_value(t, app.text.before, "Nom complet")
	session.key(s, .Escape)
	testing.expect(t, !app.text.open, "Escape gives up")
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
