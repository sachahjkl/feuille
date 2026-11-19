package feuille_thumbnail

// The thumbnail is the first page as feuille opens it: fitted in the square, its form layer hidden; a protected PDF or
// what is not a PDF gives none.

import "core:testing"
import fixture "../fixture"

@(test)
the_first_page_fits_the_square_masked :: proc(t: ^testing.T) {
	data := fixture.make_pdf({layer = true}, context.temp_allocator)
	rgba, w, h, ok := render(data, 128, context.temp_allocator)
	testing.expect(t, ok, "a thumbnail is made")
	testing.expectf(t, max(w, h) == 128 && min(w, h) > 0, "it fits the square (%d x %d)", w, h)
	testing.expect_value(t, len(rgba), w * h * 4)
	// (the field's red appearance is the layer's: it is not drawn)
	red := 0
	for i := 0; i < len(rgba); i += 4 { if rgba[i] > 200 && rgba[i + 1] < 60 && rgba[i + 2] < 60 { red += 1 } }
	testing.expect_value(t, red, 0)
}

@(test)
a_protected_pdf_and_junk_give_no_thumbnail :: proc(t: ^testing.T) {
	_, _, _, locked := render(fixture.make_pdf({password = "secret"}, context.temp_allocator), 128)
	testing.expect(t, !locked, "no password here: no thumbnail")
	_, _, _, junk := render(transmute([]u8)string("not a pdf"), 128)
	testing.expect(t, !junk, "not a PDF: no thumbnail")
}
