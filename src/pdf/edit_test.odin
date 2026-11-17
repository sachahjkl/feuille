package pdf

import "core:testing"
import fixture "../fixture"

// Pages told apart by their widths: 100, 200, 300...
@(private = "file")
widths :: proc(doc: Document) -> []f32 {
	out := make([]f32, page_count(doc), context.temp_allocator)
	for &w, i in out {
		size, _ := page_size(doc, i)
		w = size.x
	}
	return out
}

@(private = "file")
open_pages :: proc(t: ^testing.T, ws: ..f32) -> Document {
	pages := make([]fixture.Page, len(ws), context.temp_allocator)
	for w, i in ws { pages[i] = {size = {w, 300}} }
	bytes := fixture.make_pdf({pages = pages})
	doc, err := open(bytes, "")
	testing.expect_value(t, err, Error.None)
	return doc
}

@(test)
pages_turn_go_come_and_move :: proc(t: ^testing.T) {
	if !testing.expect(t, init()) { return }
	doc := open_pages(t, 100, 200, 300)
	defer close(&doc)

	// a turn: the page as shown is the other way, and its picture follows
	testing.expect(t, set_rotation(&doc, 0, 1))
	testing.expect_value(t, page_rotation(doc, 0), 1)
	size, _ := page_size(doc, 0)
	testing.expect_value(t, size, [2]f32{300, 100})

	testing.expect(t, move_page(&doc, 2, 0))
	testing.expect_value(t, widths(doc)[0], f32(300))

	scratch, ok := new_document()
	testing.expect(t, ok)
	defer close(&scratch)
	// a removal kept aside, then brought back where it was
	testing.expect(t, import_pages(&scratch, &doc, {1}, 0))
	testing.expect(t, delete_page(&doc, 1))
	testing.expect_value(t, page_count(doc), 2)
	testing.expect(t, import_pages(&doc, &scratch, {0}, 1))
	testing.expect_value(t, page_count(doc), 3)

	testing.expect(t, new_page(&doc, 3, {612, 792}))
	ws := widths(doc)
	testing.expect_value(t, len(ws), 4)
	testing.expect_value(t, ws[3], f32(612))

	// the copy keeps every edit
	saved, saved_ok := save_copy(doc, context.temp_allocator)
	testing.expect(t, saved_ok)
	again, err := open(saved, "")
	testing.expect_value(t, err, Error.None)
	defer { again.bytes = nil; close(&again) }   // (the test's memory holds the bytes)
	testing.expect_value(t, page_count(again), 4)
	testing.expect_value(t, page_rotation(again, 1), 1)
}

// The words of a block of the sample form, read under a point and changed.
@(test)
a_text_block_is_read_and_changed :: proc(t: ^testing.T) {
	if !testing.expect(t, init()) { return }
	doc, err := open(fixture.make_sample(), "")
	testing.expect_value(t, err, Error.None)
	defer close(&doc)
	// "Full name", drawn at (64, 624) in a page of 595 x 842 points
	at := [2]f32{(64 + 12) / 595.0, 1 - (624 + 3) / 842.0}
	block, ok := text_at(&doc, 0, at, context.temp_allocator)
	if !testing.expect(t, ok, "a block under the label") { return }
	testing.expect_value(t, block.text, "Full name")
	testing.expect(t, block.box[0] < at.x && at.x < block.box[2] && block.box[1] < at.y && at.y < block.box[3], "the point is in the block's box")
	testing.expect(t, !block.subset, "Helvetica, not embedded: not a subset")

	testing.expect(t, set_text(&doc, 0, block.object, "Nom complet"))
	now, now_ok := object_text_of(&doc, 0, block.object, context.temp_allocator)
	testing.expect(t, now_ok)
	testing.expect_value(t, now, "Nom complet")

	_, nothing := text_at(&doc, 0, {0.98, 0.02}, context.temp_allocator)
	testing.expect(t, !nothing, "no block in the margin")
}
