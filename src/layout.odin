package feuille

// The column of pages (src/md/data/snapshot.md, src/md/features/viewer.md): where each page stands, made when the
// snapshot, the view's width or the zoom change, never in a frame that changes none. Logical pixels throughout; the
// pictures are rendered at these sizes times the screen's scale.

import "core:math"
import "core:slice"

PAGE_GAP    :: 12.0   // between two pages
PAGE_MARGIN :: 16.0   // around the column
// The largest side of a picture, in pixels: the zoom stops where a page would pass it.
PICTURE_MAX :: 8192

Layout :: struct {
	// what it was made from
	revision: u64,
	width:    f32,   // the view's
	zoom:     f32,   // the zone's: 1 fits the widest page to the view
	// what it says
	scale:    f32,   // logical pixels per point
	tops:     [dynamic]f32,
	sizes:    [dynamic][2]f32,
	widest:   f32,   // the widest page's width
	height:   f32,   // the whole column, its margins in
}

layout_destroy :: proc(l: ^Layout) {
	delete(l.tops)
	delete(l.sizes)
	l^ = {}
}

// Whether the layout must be made again for these.
layout_stale :: proc(l: Layout, revision: u64, width, zoom: f32) -> bool {
	return l.revision != revision || l.width != width || l.zoom != zoom
}

// Lays the pages out for a view `width` wide at `zoom`; `screen`: the screen's scale (device pixels per logical one),
// which bounds the zoom by PICTURE_MAX.
layout_make :: proc(l: ^Layout, revision: u64, pages: []Snapshot_Page, width, zoom, screen: f32) {
	l.revision, l.width, l.zoom = revision, width, zoom
	clear(&l.tops)
	clear(&l.sizes)
	widest, largest: f32
	for p in pages {
		widest = max(widest, p.size.x)
		largest = max(largest, p.size.x, p.size.y)
	}
	l.scale = 0
	if widest > 0 {
		l.scale = max(width - 2 * PAGE_MARGIN, 1) / widest * zoom
		l.scale = min(l.scale, PICTURE_MAX / (largest * max(screen, 1)))
	}
	y: f32 = PAGE_MARGIN
	l.widest = 0
	for p in pages {
		append(&l.tops, y)
		size := [2]f32{math.round(p.size.x * l.scale), math.round(p.size.y * l.scale)}
		append(&l.sizes, size)
		l.widest = max(l.widest, size.x)
		y += size.y + PAGE_GAP
	}
	l.height = len(pages) > 0 ? y - PAGE_GAP + PAGE_MARGIN : 0
}

// The pages that cross [from, to), the column's own coordinates: [first, last). A binary search: no pass over the pages.
layout_range :: proc(l: Layout, from, to: f32) -> (first, last: int) {
	n := len(l.tops)
	// the first page whose bottom is below `from`
	first, _ = slice.binary_search_by(l.tops[:], from, proc(top, from: f32) -> slice.Ordering {
		return top <= from ? .Less : .Greater
	})
	first = max(first - 1, 0)
	for first < n && l.tops[first] + l.sizes[first].y < from { first += 1 }
	last = first
	for last < n && l.tops[last] < to { last += 1 }
	return
}

// The page at the column's height `y` (the nearest), and how far into it, 0 to 1. -1: no page.
layout_at :: proc(l: Layout, y: f32) -> (page: int, fraction: f32) {
	if len(l.tops) == 0 { return -1, 0 }
	first, _ := layout_range(l, y, y + 1)
	page = min(first, len(l.tops) - 1)
	h := max(l.sizes[page].y, 1)
	return page, clamp((y - l.tops[page]) / h, 0, 1)
}
