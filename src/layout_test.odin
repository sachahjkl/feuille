package feuille

import "core:testing"

@(private = "file")
pages_of :: proc(sizes: ..[2]f32) -> []Snapshot_Page {
	out := make([]Snapshot_Page, len(sizes), context.temp_allocator)
	for s, i in sizes { out[i] = {id = u64(i + 1), size = s} }
	return out
}

@(test)
the_widest_page_fits_the_view :: proc(t: ^testing.T) {
	l: Layout
	defer layout_destroy(&l)
	layout_make(&l, 1, pages_of({100, 200}, {200, 100}), 432, 1, 1)
	testing.expect_value(t, l.scale, f32(2))   // (432 - 2 * 16) / 200
	testing.expect_value(t, l.sizes[0], [2]f32{200, 400})
	testing.expect_value(t, l.sizes[1], [2]f32{400, 200})
	testing.expect_value(t, l.tops[0], f32(PAGE_MARGIN))
	testing.expect_value(t, l.tops[1], f32(PAGE_MARGIN + 400 + PAGE_GAP))
	testing.expect_value(t, l.height, f32(PAGE_MARGIN + 400 + PAGE_GAP + 200 + PAGE_MARGIN))
	testing.expect(t, !layout_stale(l, 1, 432, 1))
	testing.expect(t, layout_stale(l, 2, 432, 1), "another revision")
	testing.expect(t, layout_stale(l, 1, 500, 1), "another width")
	testing.expect(t, layout_stale(l, 1, 432, 2), "another zoom")
}

@(test)
a_range_holds_the_pages_that_cross_it :: proc(t: ^testing.T) {
	l: Layout
	defer layout_destroy(&l)
	sizes := make([][2]f32, 1000, context.temp_allocator)
	for &s in sizes { s = {100, 100} }
	layout_make(&l, 1, pages_of(..sizes), 132, 1, 1)   // (each page 100 high, one every 112)
	first, last := layout_range(l, 0, 10)   // (the margin above the first page)
	testing.expect_value(t, first, last)
	first, last = layout_range(l, 0, 20)
	testing.expect_value(t, [2]int{first, last}, [2]int{0, 1})
	first, last = layout_range(l, 16 + 112 * 500 + 50, 16 + 112 * 500 + 60)   // inside page 500
	testing.expect_value(t, [2]int{first, last}, [2]int{500, 501})
	first, last = layout_range(l, 16 + 112 * 500 + 105, 16 + 112 * 502 + 1)   // a gap, then two pages
	testing.expect_value(t, [2]int{first, last}, [2]int{501, 503})
	first, last = layout_range(l, l.height + 10, l.height + 20)
	testing.expect_value(t, first, last)
	page, fraction := layout_at(l, 16 + 112 * 7 + 25)
	testing.expect_value(t, page, 7)
	testing.expect_value(t, fraction, f32(0.25))
}

@(test)
the_zoom_stops_before_the_largest_picture :: proc(t: ^testing.T) {
	l: Layout
	defer layout_destroy(&l)
	layout_make(&l, 1, pages_of({100, 1000}), 10_000, 100, 2)
	testing.expect(t, l.sizes[0].y * 2 <= PICTURE_MAX, "the tallest side at most PICTURE_MAX pixels")
}
