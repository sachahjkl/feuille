// PDFium's C API, the part feuille uses, loaded at run time (load_linux.odin): a program that never opens a PDF starts on
// a system without the library, and init says it is missing. The binding is thin: the C handles as distinct types, and
// a few procedures that hold the rules every caller would otherwise repeat (a document keeps its bytes; a render clears
// to white first). PDFium has global state and is not thread-safe: one thread makes every call. A debug build checks it
// (claim). src/md/infrastructure/pdfium.md.
package pdf

import "base:runtime"
import "core:c"
import "core:mem"
import "core:sync"

Document_Handle :: distinct rawptr
Page_Handle     :: distinct rawptr
Bitmap_Handle   :: distinct rawptr
Form_Handle     :: distinct rawptr
Text_Page_Handle :: distinct rawptr
Object_Handle   :: distinct rawptr
Font_Handle     :: distinct rawptr

// FPDF_FORMFILLINFO, version 1, with every callback empty: the form environment exists to draw the widgets, nothing
// else (src/md/features/masked-opening.md). The C struct is a version and a row of callbacks; the room left is more
// than the header's count, all zero.
@(private)
Form_Info :: struct {
	version:   c.int,
	callbacks: [96]rawptr,
}

// Render flags (fpdfview.h). Without RENDER_ANNOT the engine draws no annotation, no form widget and no signature
// appearance: the masked opening.
RENDER_ANNOT :: 0x01

// FPDFBitmap_BGRx: four bytes a pixel, no alpha (a page is opaque). render swaps it to RGBA itself: this build of the
// engine traps on FPDF_REVERSE_BYTE_ORDER.
@(private) BITMAP_BGRX :: 3
// FPDF_SaveAsCopy's flag that drops the encryption and the restrictions (fpdf_save.h).
@(private) SAVE_REMOVE_SECURITY :: 3

// Why a load failed (FPDF_GetLastError).
Error :: enum u8 {
	None,
	Unknown,
	File,
	Format,     // not a PDF, or damaged
	Password,   // a password is needed, or the one given is wrong
	Security,   // a security handler the engine does not know
	Page,
	No_Library, // libpdfium is not on this system
}

// FPDF_FILEWRITE: what FPDF_SaveAsCopy writes through. The C struct has no user pointer: Sink embeds it first and the
// callback casts back.
@(private)
File_Write :: struct {
	version:     c.int,
	write_block: proc "c" (self: ^File_Write, data: rawptr, size: c.ulong) -> c.int,
}

@(private)
Sink :: struct {
	using write: File_Write,
	bytes:       [dynamic]u8,
	ctx:         runtime.Context,
}

@(private)
Size_F :: struct {
	width, height: f32,
}

// The library's procedures, filled by load_library.
@(private)
Api :: struct {
	init_library:          proc "c" (),
	get_last_error:        proc "c" () -> c.ulong,
	load_mem_document64:   proc "c" (data: rawptr, size: c.size_t, password: cstring) -> Document_Handle,
	close_document:        proc "c" (doc: Document_Handle),
	get_page_count:        proc "c" (doc: Document_Handle) -> c.int,
	get_page_size_by_index_f: proc "c" (doc: Document_Handle, index: c.int, size: ^Size_F) -> c.int,
	load_page:             proc "c" (doc: Document_Handle, index: c.int) -> Page_Handle,
	close_page:            proc "c" (page: Page_Handle),
	page_get_rotation:     proc "c" (page: Page_Handle) -> c.int,
	bitmap_create_ex:      proc "c" (width, height, format: c.int, first_scan: rawptr, stride: c.int) -> Bitmap_Handle,
	bitmap_destroy:        proc "c" (bitmap: Bitmap_Handle),
	render_page_bitmap:    proc "c" (bitmap: Bitmap_Handle, page: Page_Handle, start_x, start_y, size_x, size_y, rotate, flags: c.int),
	save_as_copy:          proc "c" (doc: Document_Handle, file_write: ^File_Write, flags: c.ulong) -> c.int,
	init_form:             proc "c" (doc: Document_Handle, info: ^Form_Info) -> Form_Handle,
	exit_form:             proc "c" (form: Form_Handle),
	ffl_draw:              proc "c" (form: Form_Handle, bitmap: Bitmap_Handle, page: Page_Handle, start_x, start_y, size_x, size_y, rotate, flags: c.int),
	// the edits (edit.odin)
	page_set_rotation:     proc "c" (page: Page_Handle, rotate: c.int),
	page_delete:           proc "c" (doc: Document_Handle, index: c.int),
	page_new:              proc "c" (doc: Document_Handle, index: c.int, width, height: f64) -> Page_Handle,
	import_pages_by_index: proc "c" (dest, src: Document_Handle, indices: [^]c.int, length: c.ulong, index: c.int) -> c.int,
	move_pages:            proc "c" (doc: Document_Handle, indices: [^]c.int, length: c.ulong, dest_index: c.int) -> c.int,
	create_new_document:   proc "c" () -> Document_Handle,
	device_to_page:        proc "c" (page: Page_Handle, start_x, start_y, size_x, size_y, rotate, device_x, device_y: c.int, page_x, page_y: ^f64) -> c.int,
	page_to_device:        proc "c" (page: Page_Handle, start_x, start_y, size_x, size_y, rotate: c.int, page_x, page_y: f64, device_x, device_y: ^c.int) -> c.int,
	text_load_page:        proc "c" (page: Page_Handle) -> Text_Page_Handle,
	text_close_page:       proc "c" (text: Text_Page_Handle),
	text_char_at_pos:      proc "c" (text: Text_Page_Handle, x, y, x_tolerance, y_tolerance: f64) -> c.int,
	text_object_of_char:   proc "c" (text: Text_Page_Handle, index: c.int) -> Object_Handle,
	text_object_text:      proc "c" (object: Object_Handle, text: Text_Page_Handle, buffer: [^]u16, length: c.ulong) -> c.ulong,
	object_bounds:         proc "c" (object: Object_Handle, left, bottom, right, top: ^f32) -> c.int,
	text_set_text:         proc "c" (object: Object_Handle, text: [^]u16) -> c.int,
	page_generate_content: proc "c" (page: Page_Handle) -> c.int,
	text_object_font:      proc "c" (object: Object_Handle) -> Font_Handle,
	font_base_name:        proc "c" (font: Font_Handle, buffer: [^]u8, length: c.size_t) -> c.size_t,
	page_count_objects:    proc "c" (page: Page_Handle) -> c.int,
	page_get_object:       proc "c" (page: Page_Handle, index: c.int) -> Object_Handle,
	object_type:           proc "c" (object: Object_Handle) -> c.int,
}

// Fills the table by the library's names, `sym` being the system's lookup (dlsym, GetProcAddress) on handle `h`; true
// when every one was found.
@(private)
api_fill :: proc(a: ^Api, h: rawptr, sym: proc(h: rawptr, name: cstring) -> rawptr) -> bool {
	a.init_library = auto_cast sym(h, "FPDF_InitLibrary")
	a.get_last_error = auto_cast sym(h, "FPDF_GetLastError")
	a.load_mem_document64 = auto_cast sym(h, "FPDF_LoadMemDocument64")
	a.close_document = auto_cast sym(h, "FPDF_CloseDocument")
	a.get_page_count = auto_cast sym(h, "FPDF_GetPageCount")
	a.get_page_size_by_index_f = auto_cast sym(h, "FPDF_GetPageSizeByIndexF")
	a.load_page = auto_cast sym(h, "FPDF_LoadPage")
	a.close_page = auto_cast sym(h, "FPDF_ClosePage")
	a.page_get_rotation = auto_cast sym(h, "FPDFPage_GetRotation")
	a.bitmap_create_ex = auto_cast sym(h, "FPDFBitmap_CreateEx")
	a.bitmap_destroy = auto_cast sym(h, "FPDFBitmap_Destroy")
	a.render_page_bitmap = auto_cast sym(h, "FPDF_RenderPageBitmap")
	a.save_as_copy = auto_cast sym(h, "FPDF_SaveAsCopy")
	a.init_form = auto_cast sym(h, "FPDFDOC_InitFormFillEnvironment")
	a.exit_form = auto_cast sym(h, "FPDFDOC_ExitFormFillEnvironment")
	a.ffl_draw = auto_cast sym(h, "FPDF_FFLDraw")
	a.page_set_rotation = auto_cast sym(h, "FPDFPage_SetRotation")
	a.page_delete = auto_cast sym(h, "FPDFPage_Delete")
	a.page_new = auto_cast sym(h, "FPDFPage_New")
	a.import_pages_by_index = auto_cast sym(h, "FPDF_ImportPagesByIndex")
	a.move_pages = auto_cast sym(h, "FPDF_MovePages")
	a.create_new_document = auto_cast sym(h, "FPDF_CreateNewDocument")
	a.device_to_page = auto_cast sym(h, "FPDF_DeviceToPage")
	a.page_to_device = auto_cast sym(h, "FPDF_PageToDevice")
	a.text_load_page = auto_cast sym(h, "FPDFText_LoadPage")
	a.text_close_page = auto_cast sym(h, "FPDFText_ClosePage")
	a.text_char_at_pos = auto_cast sym(h, "FPDFText_GetCharIndexAtPos")
	a.text_object_of_char = auto_cast sym(h, "FPDFText_GetTextObject")
	a.text_object_text = auto_cast sym(h, "FPDFTextObj_GetText")
	a.object_bounds = auto_cast sym(h, "FPDFPageObj_GetBounds")
	a.text_set_text = auto_cast sym(h, "FPDFText_SetText")
	a.page_generate_content = auto_cast sym(h, "FPDFPage_GenerateContent")
	a.text_object_font = auto_cast sym(h, "FPDFTextObj_GetFont")
	a.font_base_name = auto_cast sym(h, "FPDFFont_GetBaseFontName")
	a.page_count_objects = auto_cast sym(h, "FPDFPage_CountObjects")
	a.page_get_object = auto_cast sym(h, "FPDFPage_GetObject")
	a.object_type = auto_cast sym(h, "FPDFPageObj_GetType")
	return api_complete(a^)
}

// Whether every procedure was found: a library without one of them (an older build) counts as none.
@(private)
api_complete :: proc(a: Api) -> bool {
	a := a
	words := transmute([size_of(Api) / size_of(rawptr)]rawptr)a
	for w in words { if w == nil { return false } }
	return true
}

@(private) api:       Api
@(private) api_once:  sync.Once
@(private) api_found: bool
// The thread that makes the calls (claim); 0: none yet.
@(private) owner:     int

@(private = "file")
start :: proc() {
	api_found = load_library(&api)
	if api_found { api.init_library() }
}

// Loads libpdfium and starts the engine, once for the process, and claims the calling thread. false: no library.
init :: proc() -> bool {
	sync.once_do(&api_once, start)
	if api_found { claim() }
	return api_found
}

// The calling thread makes the engine's calls from now on. A worker that takes over the engine (a test's new
// program) claims it; two threads never use it at the same time.
claim :: proc() {
	sync.atomic_store(&owner, sync.current_thread_id())
}

@(private)
check_owner :: #force_inline proc(loc := #caller_location) {
	when ODIN_DEBUG {
		assert(sync.atomic_load(&owner) == sync.current_thread_id(), "pdf: an engine call from a thread that did not claim it", loc)
	}
}

// An open document and the bytes it reads: the engine reads them lazily for as long as the document is open, so they
// live and die with it.
Document :: struct {
	handle: Document_Handle,
	bytes:  []u8,
	// the drawing-only form environment, made by the first render that shows the layer (nil: never shown)
	form:      Form_Handle,
	form_info: ^Form_Info,   // (it must outlive the environment)
	allocator: runtime.Allocator,   // the bytes' and the form information's
}

// Opens `bytes`, made with `allocator`, which the document then owns: close frees them. A failed open frees nothing:
// the caller keeps its bytes (to try again with a password). password "": none.
open :: proc(bytes: []u8, password: string, allocator := context.allocator) -> (doc: Document, err: Error) {
	if !api_found { return {}, .No_Library }
	check_owner()
	if len(bytes) == 0 { return {}, .Format }
	pw := cstring(nil)
	if password != "" { pw = cstring_of(password) }
	h := api.load_mem_document64(raw_data(bytes), c.size_t(len(bytes)), pw)
	if h == nil { return {}, last_error() }
	return {handle = h, bytes = bytes, allocator = allocator}, .None
}

// Closes the document and frees its bytes.
close :: proc(doc: ^Document) {
	if doc.handle != nil {
		check_owner()
		if doc.form != nil { api.exit_form(doc.form) }
		api.close_document(doc.handle)
	}
	free(doc.form_info, doc.allocator)
	delete(doc.bytes, doc.allocator)
	doc^ = {}
}

@(private = "file")
last_error :: proc() -> Error {
	switch api.get_last_error() {
	case 0: return .Unknown   // (a failed load that says success: still a failure)
	case 2: return .File
	case 3: return .Format
	case 4: return .Password
	case 5: return .Security
	case 6: return .Page
	}
	return .Unknown
}

@(private = "file")
cstring_of :: proc(s: string) -> cstring {
	b := make([]u8, len(s) + 1, context.temp_allocator)
	copy(b, s)
	return cstring(raw_data(b))
}

page_count :: proc(doc: Document) -> int {
	check_owner()
	return int(api.get_page_count(doc.handle))
}

// The page's size in points (1/72 inch), as shown: its rotation applied.
page_size :: proc(doc: Document, index: int) -> (size: [2]f32, ok: bool) {
	check_owner()
	s: Size_F
	if api.get_page_size_by_index_f(doc.handle, c.int(index), &s) == 0 { return {}, false }
	return {s.width, s.height}, true
}

// The page's own rotation (/Rotate), in quarter turns clockwise: 0 to 3.
page_rotation :: proc(doc: Document, index: int) -> int {
	check_owner()
	page := api.load_page(doc.handle, c.int(index))
	if page == nil { return 0 }
	defer api.close_page(page)
	return int(api.page_get_rotation(page))
}

// The page at `index`, rendered `width` x `height` pixels on white, as RGBA (opaque), in `allocator`. `layer`: the
// annotations and the form widgets drawn too; false: the page's own content only. nil: no such page, or no room.
render :: proc(doc: ^Document, index, width, height: int, layer: bool, allocator := context.allocator) -> []u8 {
	check_owner()
	if width <= 0 || height <= 0 { return nil }
	page := api.load_page(doc.handle, c.int(index))
	if page == nil { return nil }
	defer api.close_page(page)
	pixels, err := make([]u8, width * height * 4, allocator)
	if err != nil { return nil }
	// (the engine draws the page's content only: the paper is ours, opaque white)
	mem.set(raw_data(pixels), 0xFF, len(pixels))
	bitmap := api.bitmap_create_ex(c.int(width), c.int(height), BITMAP_BGRX, raw_data(pixels), c.int(width * 4))
	if bitmap == nil {
		delete(pixels, allocator)
		return nil
	}
	defer api.bitmap_destroy(bitmap)
	flags: c.int = layer ? RENDER_ANNOT : 0
	api.render_page_bitmap(bitmap, page, 0, 0, c.int(width), c.int(height), 0, flags)
	if layer {
		if doc.form == nil {
			doc.form_info = new(Form_Info, doc.allocator)
			doc.form_info.version = 1
			doc.form = api.init_form(doc.handle, doc.form_info)
		}
		if doc.form != nil { api.ffl_draw(doc.form, bitmap, page, 0, 0, c.int(width), c.int(height), 0, flags) }
	}
	for i := 0; i < len(pixels); i += 4 {
		pixels[i], pixels[i + 2], pixels[i + 3] = pixels[i + 2], pixels[i], 0xFF
	}
	return pixels
}

// A copy of the document as bytes, its encryption and restrictions dropped, in `allocator`. The document is not
// changed. ok false: the engine refused.
save_copy :: proc(doc: Document, allocator := context.allocator) -> (bytes: []u8, ok: bool) {
	check_owner()
	s := Sink{write = {version = 1, write_block = sink_write}, bytes = make([dynamic]u8, allocator), ctx = context}
	if api.save_as_copy(doc.handle, &s.write, SAVE_REMOVE_SECURITY) == 0 {
		delete(s.bytes)
		return nil, false
	}
	return s.bytes[:], true
}

@(private = "file")
sink_write :: proc "c" (self: ^File_Write, data: rawptr, size: c.ulong) -> c.int {
	s := (^Sink)(self)
	context = s.ctx
	append(&s.bytes, ..([^]u8)(data)[:size])
	return 1
}
