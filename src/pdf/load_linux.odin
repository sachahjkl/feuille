#+build linux
package pdf

// libpdfium.so with dlopen: the one beside the program first (a release's archive carries it), then the system's library
// path (the flake's shell and package). The handle is never closed: the engine lives as long as the process.

import "core:path/filepath"
import "core:strings"
import "core:sys/posix"

@(private)
load_library :: proc(a: ^Api) -> bool {
	for name in library_candidates() {
		h := posix.dlopen(name, posix.RTLD_LOCAL + {.NOW})
		if h == nil { continue }
		if fill(a, h) { return true }
		posix.dlclose(h)
		a^ = {}
	}
	return false
}

// The library beside the executable (its real path: /proc/self/exe), then the bare name for the system's search.
@(private = "file")
library_candidates :: proc() -> []cstring {
	out := make([dynamic]cstring, context.temp_allocator)
	buf: [4096]u8
	if n := posix.readlink("/proc/self/exe", raw_data(buf[:]), len(buf) - 1); n > 0 {
		dir := filepath.dir(string(buf[:n]))
		append(&out, strings.clone_to_cstring(strings.concatenate({dir, "/libpdfium.so"}, context.temp_allocator), context.temp_allocator))
	}
	append(&out, "libpdfium.so")
	return out[:]
}

@(private = "file")
fill :: proc(a: ^Api, h: posix.Symbol_Table) -> bool {
	sym :: proc(h: posix.Symbol_Table, name: cstring) -> rawptr { return posix.dlsym(h, name) }
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
	return api_complete(a^)
}
