#+build linux
package pdf

// libpdfium.so with dlopen: the flake's PDFium is on LD_LIBRARY_PATH in the development shell and in the package's
// wrapper. The handle is never closed: the engine lives as long as the process.

import "core:sys/posix"

@(private)
load_library :: proc(a: ^Api) -> bool {
	h := posix.dlopen("libpdfium.so", posix.RTLD_LOCAL + {.NOW})
	if h == nil { return false }
	a.init_library = auto_cast posix.dlsym(h, "FPDF_InitLibrary")
	a.get_last_error = auto_cast posix.dlsym(h, "FPDF_GetLastError")
	a.load_mem_document64 = auto_cast posix.dlsym(h, "FPDF_LoadMemDocument64")
	a.close_document = auto_cast posix.dlsym(h, "FPDF_CloseDocument")
	a.get_page_count = auto_cast posix.dlsym(h, "FPDF_GetPageCount")
	a.get_page_size_by_index_f = auto_cast posix.dlsym(h, "FPDF_GetPageSizeByIndexF")
	a.load_page = auto_cast posix.dlsym(h, "FPDF_LoadPage")
	a.close_page = auto_cast posix.dlsym(h, "FPDF_ClosePage")
	a.page_get_rotation = auto_cast posix.dlsym(h, "FPDFPage_GetRotation")
	a.bitmap_create_ex = auto_cast posix.dlsym(h, "FPDFBitmap_CreateEx")
	a.bitmap_destroy = auto_cast posix.dlsym(h, "FPDFBitmap_Destroy")
	a.render_page_bitmap = auto_cast posix.dlsym(h, "FPDF_RenderPageBitmap")
	a.save_as_copy = auto_cast posix.dlsym(h, "FPDF_SaveAsCopy")
	a.init_form = auto_cast posix.dlsym(h, "FPDFDOC_InitFormFillEnvironment")
	a.exit_form = auto_cast posix.dlsym(h, "FPDFDOC_ExitFormFillEnvironment")
	a.ffl_draw = auto_cast posix.dlsym(h, "FPDF_FFLDraw")
	if a.init_library == nil || a.get_last_error == nil || a.load_mem_document64 == nil || a.close_document == nil ||
	   a.get_page_count == nil || a.get_page_size_by_index_f == nil || a.load_page == nil || a.close_page == nil ||
	   a.page_get_rotation == nil || a.bitmap_create_ex == nil || a.bitmap_destroy == nil || a.render_page_bitmap == nil || a.save_as_copy == nil ||
	   a.init_form == nil || a.exit_form == nil || a.ffl_draw == nil {
		// (an older library without one of them: as if there were none)
		posix.dlclose(h)
		a^ = {}
		return false
	}
	return true
}
