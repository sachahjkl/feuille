// feuille's thumbnail provider: the DLL Windows Explorer loads to show a PDF's first page (src/md/features/thumbnails.md).
// The toolkit builds it (toolbox Project.thumbnailer, -build-mode:dll), feuille.exe embeds its bytes, and the install
// writes it beside the program and registers it (gt:desktop's Thumbnails part). The COM server is the toolkit's
// (gt:shell_thumbnail); this package only says who it is and how a page is drawn.
package feuille_thumbnailer

import shell_thumbnail "gt:shell_thumbnail"
import thumbnail "../thumbnail"

@(init)
thumbnailer_init :: proc "contextless" () {
	shell_thumbnail.set(thumbnail.CLSID, proc(data: []u8, size: int) -> (rgba: []u8, width, height: int, ok: bool) {
		return thumbnail.render(data, size)
	})
}

when ODIN_OS == .Windows {
	@(export, link_name = "DllGetClassObject")
	dll_get_class_object :: proc "system" (rclsid, riid: ^shell_thumbnail.GUID, ppv: ^rawptr) -> shell_thumbnail.HRESULT {
		return shell_thumbnail.dll_get_class_object(rclsid, riid, ppv)
	}

	@(export, link_name = "DllCanUnloadNow")
	dll_can_unload_now :: proc "system" () -> shell_thumbnail.HRESULT {
		return shell_thumbnail.dll_can_unload_now()
	}
}
