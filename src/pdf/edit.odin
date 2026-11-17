package pdf

// The edits the engine makes in place (src/md/features/page-edits.md, text-editing.md): a page's rotation, a page
// removed, made, imported or moved, a text object's words. Each is one call of the engine; the worker keeps their
// inverses for undo. Pages are named by their index here: the worker maps its identities to indices.

import "core:c"
import "core:strings"
import "core:unicode/utf16"

// A document of the engine's own, empty, with no bytes behind it: the scratch where removed pages wait for an undo,
// the document an extract fills. close() closes it.
new_document :: proc(allocator := context.allocator) -> (doc: Document, ok: bool) {
	if !api_found { return {}, false }
	check_owner()
	h := api.create_new_document()
	if h == nil { return {}, false }
	return {handle = h, allocator = allocator}, true
}

// The page's /Rotate, in quarter turns clockwise (0 to 3).
set_rotation :: proc(doc: ^Document, index, quarters: int) -> bool {
	check_owner()
	page := api.load_page(doc.handle, c.int(index))
	if page == nil { return false }
	defer api.close_page(page)
	api.page_set_rotation(page, c.int(((quarters % 4) + 4) % 4))
	return true
}

delete_page :: proc(doc: ^Document, index: int) -> bool {
	check_owner()
	if index < 0 || index >= page_count(doc^) { return false }
	api.page_delete(doc.handle, c.int(index))
	return true
}

// A blank page of `size` points at `index` (its position after the insertion).
new_page :: proc(doc: ^Document, index: int, size: [2]f32) -> bool {
	check_owner()
	page := api.page_new(doc.handle, c.int(index), f64(size.x), f64(size.y))
	if page == nil { return false }
	api.close_page(page)
	return true
}

// The pages `indices` of `from`, in that order, inserted into `into` at `at`. `from` is only read.
import_pages :: proc(into, from: ^Document, indices: []int, at: int) -> bool {
	check_owner()
	if len(indices) == 0 { return true }
	ci := make([]c.int, len(indices), context.temp_allocator)
	for v, i in indices { ci[i] = c.int(v) }
	return api.import_pages_by_index(into.handle, from.handle, raw_data(ci), c.ulong(len(ci)), c.int(at)) != 0
}

// The page at `from` moved so that it ends at index `to`.
move_page :: proc(doc: ^Document, from, to: int) -> bool {
	check_owner()
	n := page_count(doc^)
	if from < 0 || from >= n || to < 0 || to >= n { return false }
	if from == to { return true }
	index := [1]c.int{c.int(from)}
	return api.move_pages(doc.handle, raw_data(index[:]), 1, c.int(to)) != 0
}

// A block of text under a point: the text object's index on its page, its words, its box as shares of the page shown
// (x0, y0, x1, y1 from the top left), its font's name, and whether that font is an embedded subset (its new letters may
// be missing: text-editing.md).
Text_Block :: struct {
	object: int,
	text:   string,
	box:    [4]f32,
	font:   string,
	subset: bool,
}

// The text block at `at` (shares of the page shown, from its top left) of page `index`, in `allocator`. ok false: no
// text there.
text_at :: proc(doc: ^Document, index: int, at: [2]f32, allocator := context.allocator) -> (block: Text_Block, ok: bool) {
	check_owner()
	page := api.load_page(doc.handle, c.int(index))
	if page == nil { return }
	defer api.close_page(page)
	// (device coordinates of a large square: the page shown, its rotation applied, mapped to its own points)
	D :: 10_000
	px, py: f64
	if api.device_to_page(page, 0, 0, D, D, 0, c.int(at.x * D), c.int(at.y * D), &px, &py) == 0 { return }
	tp := api.text_load_page(page)
	if tp == nil { return }
	defer api.text_close_page(tp)
	ch := api.text_char_at_pos(tp, px, py, 4, 4)
	if ch < 0 { return }
	object := api.text_object_of_char(tp, ch)
	if object == nil { return }
	block.object = -1
	for i in 0 ..< int(api.page_count_objects(page)) {
		if api.page_get_object(page, c.int(i)) == object { block.object = i; break }
	}
	if block.object < 0 { return }
	block.text = object_text(object, tp, allocator)
	l, b, r, t: f32
	if api.object_bounds(object, &l, &b, &r, &t) != 0 {
		x0, y0, x1, y1: c.int
		api.page_to_device(page, 0, 0, D, D, 0, f64(l), f64(t), &x0, &y0)
		api.page_to_device(page, 0, 0, D, D, 0, f64(r), f64(b), &x1, &y1)
		block.box = {f32(min(x0, x1)) / D, f32(min(y0, y1)) / D, f32(max(x0, x1)) / D, f32(max(y0, y1)) / D}
	}
	if font := api.text_object_font(object); font != nil {
		buf: [256]u8
		n := int(api.font_base_name(font, raw_data(buf[:]), len(buf)))
		if n > 1 {
			block.font = strings.clone(string(buf[:n - 1]), allocator)
			// (a subset's name is six capitals and a plus sign: "ABCDEF+Name")
			block.subset = len(block.font) > 7 && block.font[6] == '+'
		}
	}
	return block, true
}

// The words of the text object `object` of page `index` (its text of now).
object_text_of :: proc(doc: ^Document, index, object: int, allocator := context.allocator) -> (text: string, ok: bool) {
	check_owner()
	page := api.load_page(doc.handle, c.int(index))
	if page == nil { return }
	defer api.close_page(page)
	o := api.page_get_object(page, c.int(object))
	if o == nil || api.object_type(o) != OBJECT_TEXT { return }
	tp := api.text_load_page(page)
	if tp == nil { return }
	defer api.text_close_page(tp)
	return object_text(o, tp, allocator), true
}

// Sets the words of text object `object` of page `index`, and writes the page's content again.
set_text :: proc(doc: ^Document, index, object: int, text: string) -> bool {
	check_owner()
	page := api.load_page(doc.handle, c.int(index))
	if page == nil { return false }
	defer api.close_page(page)
	o := api.page_get_object(page, c.int(object))
	if o == nil || api.object_type(o) != OBJECT_TEXT { return false }
	wide := make([]u16, len(text) * 2 + 1, context.temp_allocator)
	n := utf16.encode_string(wide, text)
	wide[n] = 0
	if api.text_set_text(o, raw_data(wide)) == 0 { return false }
	return api.page_generate_content(page) != 0
}

// FPDF_PAGEOBJ_TEXT.
@(private) OBJECT_TEXT :: 1

@(private = "file")
object_text :: proc(object: Object_Handle, tp: Text_Page_Handle, allocator := context.allocator) -> string {
	size := int(api.text_object_text(object, tp, nil, 0))   // (bytes, the closing zero in)
	if size <= 2 { return strings.clone("", allocator) }
	wide := make([]u16, size / 2, context.temp_allocator)
	api.text_object_text(object, tp, raw_data(wide), c.ulong(size))
	out := make([]u8, len(wide) * 3, context.temp_allocator)
	n := utf16.decode_to_utf8(out, wide[:len(wide) - 1])
	return strings.clone(string(out[:n]), allocator)
}
