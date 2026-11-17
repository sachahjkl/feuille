#+build windows
package pdf

// pdfium.dll with LoadLibraryW: Windows looks in the program's own folder first (a release's archive carries the DLL
// beside feuille.exe). The handle is never freed: the engine lives as long as the process.

import win "core:sys/windows"

@(private)
load_library :: proc(a: ^Api) -> bool {
	h := win.LoadLibraryW(win.L("pdfium.dll"))
	if h == nil { return false }
	sym :: proc(h: win.HMODULE, name: cstring) -> rawptr { return rawptr(win.GetProcAddress(h, name)) }
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
	if !api_complete(a^) {
		win.FreeLibrary(h)
		a^ = {}
		return false
	}
	return true
}
