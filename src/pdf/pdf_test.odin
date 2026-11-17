package pdf

// The engine's tests, with no window and no file of the person: the documents come from the tests' writer.

import "core:testing"
import fixture "../fixture"

BLUE  :: [4]u8{0, 0, 255, 255}
RED   :: [4]u8{255, 0, 0, 255}
GREEN :: [4]u8{0, 255, 0, 255}
WHITE :: [4]u8{255, 255, 255, 255}

// The pixel at (x, y) of a page rendered at one pixel per point, given in the page's points (y up).
@(private = "file")
at :: proc(pixels: []u8, size: [2]int, x, y: f32) -> [4]u8 {
	px, py := int(x), size.y - 1 - int(y)
	i := (py * size.x + px) * 4
	return {pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]}
}

// Inside a rectangle of the fixture (x, y, width, height in points).
@(private = "file")
centre :: proc(r: [4]f32) -> (x, y: f32) { return r[0] + r[2] / 2, r[1] + r[3] / 2 }

@(private = "file")
open_bytes :: proc(t: ^testing.T, bytes: []u8, password: string, loc := #caller_location) -> Document {
	owned := make([]u8, len(bytes))
	copy(owned, bytes)
	doc, err := open(owned, password)
	if !testing.expect_value(t, err, Error.None, loc = loc) { delete(owned) }
	return doc
}

// The day-one test (src/md/features/masked-opening.md): a document that blocks other readers opens, masked.
@(test)
the_blocked_document_opens_masked :: proc(t: ^testing.T) {
	if !testing.expect(t, init(), "libpdfium loads (nix develop puts it on the library path)") { return }
	bytes := fixture.make_pdf({layer = true, password = "secret"}, context.temp_allocator)

	// without the password: the password error, at once
	_, err := open(bytes, "")
	testing.expect_value(t, err, Error.Password)
	_, err = open(bytes, "wrong")
	testing.expect_value(t, err, Error.Password)

	doc := open_bytes(t, bytes, "secret")
	defer close(&doc)
	testing.expect_value(t, page_count(doc), 1)
	size, ok := page_size(doc, 0)
	testing.expect(t, ok)
	testing.expect_value(t, size, [2]f32{200, 200})

	// hidden: the page's own content, none of the layer
	masked := render(&doc, 0, 200, 200, false, context.temp_allocator)
	testing.expect_value(t, at(masked, {200, 200}, centre(fixture.BASE_RECT)), BLUE)
	testing.expect_value(t, at(masked, {200, 200}, centre(fixture.FIELD_RECT)), WHITE)
	testing.expect_value(t, at(masked, {200, 200}, centre(fixture.SIGNATURE_RECT)), WHITE)
	testing.expect_value(t, at(masked, {200, 200}, centre(fixture.NOTE_RECT)), WHITE)
	testing.expect(t, doc.form == nil, "no form environment while the layer is hidden")

	// shown: the appearances come
	shown := render(&doc, 0, 200, 200, true, context.temp_allocator)
	testing.expect_value(t, at(shown, {200, 200}, centre(fixture.BASE_RECT)), BLUE)
	testing.expect_value(t, at(shown, {200, 200}, centre(fixture.FIELD_RECT)), RED)
	testing.expect_value(t, at(shown, {200, 200}, centre(fixture.SIGNATURE_RECT)), GREEN)
	testing.expect(t, at(shown, {200, 200}, centre(fixture.NOTE_RECT)) != WHITE, "the note's icon is drawn")

	// hidden again: the layer goes, the environment stays for the next show
	hidden := render(&doc, 0, 200, 200, false, context.temp_allocator)
	testing.expect_value(t, at(hidden, {200, 200}, centre(fixture.FIELD_RECT)), WHITE)

	// the copy has no password, and the same page
	saved, saved_ok := save_copy(doc, context.temp_allocator)
	testing.expect(t, saved_ok, "the copy is made")
	copy_doc := open_bytes(t, saved, "")
	defer close(&copy_doc)
	again := render(&copy_doc, 0, 200, 200, false, context.temp_allocator)
	testing.expect_value(t, at(again, {200, 200}, centre(fixture.BASE_RECT)), BLUE)
}

@(test)
pages_keep_their_sizes_and_rotations :: proc(t: ^testing.T) {
	if !testing.expect(t, init()) { return }
	bytes := fixture.make_pdf({pages = {{size = {200, 300}}, {size = {200, 300}, rotate = 90}, {size = {400, 100}}}}, context.temp_allocator)
	doc := open_bytes(t, bytes, "")
	defer close(&doc)
	testing.expect_value(t, page_count(doc), 3)
	s0, _ := page_size(doc, 0)
	s1, _ := page_size(doc, 1)
	s2, _ := page_size(doc, 2)
	testing.expect_value(t, s0, [2]f32{200, 300})
	testing.expect_value(t, s1, [2]f32{300, 200})   // (as shown: turned)
	testing.expect_value(t, s2, [2]f32{400, 100})
	testing.expect_value(t, page_rotation(doc, 1), 1)
	_, missing := page_size(doc, 3)
	testing.expect(t, !missing, "no fourth page")
	testing.expect(t, render(&doc, 3, 10, 10, false, context.temp_allocator) == nil, "no picture of a page that is not there")
}

@(test)
what_is_not_a_pdf_is_refused :: proc(t: ^testing.T) {
	if !testing.expect(t, init()) { return }
	junk := "this is not a pdf"
	_, err := open(transmute([]u8)junk, "")
	testing.expect_value(t, err, Error.Format)
	_, err = open(nil, "")
	testing.expect_value(t, err, Error.Format)
}
