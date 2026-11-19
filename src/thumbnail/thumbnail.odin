// The picture of a PDF the file managers show (src/md/features/thumbnails.md): its first page, as feuille opens it
// (the form layer hidden), fitted in a square. Shared by `feuille --thumbnail` (Linux's thumbnailers run the program)
// and by the thumbnail provider Windows Explorer loads (src/thumbnailer). It may run on any thread: gt:pdf is shared.
package feuille_thumbnail

import pdf "gt:pdf"

// feuille's thumbnail provider's COM class, the DLL's and the install's: one for good (an install registers it; a new
// one would leave the old registration behind).
CLSID :: "{6F5C1C2E-3B8A-4E1D-9A57-2C0F4B8E7D31}"

// The first page of the PDF in `data`, fitted in `size` x `size` pixels: straight RGBA. ok false: not a PDF, a
// protected one (no password to give here), or the engine refused it.
render :: proc(data: []u8, size: int, allocator := context.allocator) -> (rgba: []u8, width, height: int, ok: bool) {
	if size <= 0 { return }
	src, err := pdf.open(data)
	if err != .None { return }
	defer pdf.close(src)
	page := pdf.Page{source = src, index = 0}
	shown := pdf.shown_size(page)
	if shown.x <= 0 || shown.y <= 0 { return }
	k := f32(size) / max(shown.x, shown.y)
	width, height = max(int(shown.x * k + 0.5), 1), max(int(shown.y * k + 0.5), 1)
	rgba = pdf.render(page, width, height, false, allocator)
	ok = rgba != nil
	return
}
