#+build windows
package pdf

// pdfium.dll with LoadLibraryW: Windows looks in the program's own folder first (a release's archive carries the DLL
// beside feuille.exe). The handle is never freed: the engine lives as long as the process.

import win "core:sys/windows"

@(private)
load_library :: proc(a: ^Api) -> bool {
	h := win.LoadLibraryW(win.L("pdfium.dll"))
	if h == nil { return false }
	sym :: proc(h: rawptr, name: cstring) -> rawptr { return rawptr(win.GetProcAddress(win.HMODULE(h), name)) }
	if !api_fill(a, rawptr(h), sym) {
		win.FreeLibrary(h)
		a^ = {}
		return false
	}
	return true
}
