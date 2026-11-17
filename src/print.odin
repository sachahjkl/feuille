package feuille

// Print: the system's dialog, then each page of the document at the printer's resolution (platform.print_document). It
// runs on the worker's printing thread, never the interface's: the dialog waits for the person, the pages take their
// time. The pages are a copy of the list as it was asked (an edit made while it prints is not printed). They go as
// feuille renders them, band by band; on Linux with the layer shown, the document goes as a PDF the print system reads
// itself (its text stays text).
// A document closed while it prints stops giving pages: what is left fails, nothing crashes.

import "core:strings"
import pdf "gt:pdf"
import "gt:platform"
import "gt:ui"

@(private = "file")
Print_Job :: struct {
	pages:  []pdf.Page,   // owned, with their stamps
	file:   []u8,         // owned: the document as a PDF (Linux)
	title:  string,       // owned
	layer:  bool,
	window: ^platform.Window,
	// the page rendered last, whole: the dialog asks a page band by band
	cached:      int,
	cached_size: [2]int,
	pixels:      []u8,
	// the answer
	status: platform.Print_Status,
	user:   rawptr,
	state:  ^ui.State,
	done:   ui.Post_Proc,
}

// What a print came to, posted to the interface.
Printed :: struct {
	status: platform.Print_Status,
	user:   rawptr,
}

print_start :: proc(w: ^Worker, title: string, layer: bool) {
	if len(w.pages) == 0 { return }
	// (a headless window, the tests': no dialog of the system, ever)
	if w.answers.window == nil {
		p := new(Printed)
		p^ = {status = .Unsupported, user = w.answers.user}
		if !ui.post(w.answers.state, w.answers.printed, p) { free(p) }
		return
	}
	j := new(Print_Job, w.allocator)
	j^ = {pages = pages_clone(w, w.allocator), title = strings.clone(title, w.allocator), layer = layer, window = w.answers.window,
		cached = -1, user = w.answers.user, state = w.answers.state, done = w.answers.printed}
	when ODIN_OS == .Linux {
		// (the print system reads a PDF itself, its text sharp at any resolution; but it draws the annotations of the
		// file: with the layer hidden, the pages go as feuille renders them)
		if layer { j.file, _ = pdf.write(j.pages, w.base, w.allocator) }
	}
	tasks_add_print(w, j)
}

@(private = "file")
tasks_add_print :: proc(w: ^Worker, j: ^Print_Job) {
	print_add(w, proc(data: rawptr) {
		j := (^Print_Job)(data)
		doc := platform.Print_Document{
			title = j.title, page_count = len(j.pages), user = j, pdf = j.file,
			page_size = proc(user: rawptr, page: int) -> [2]f64 {
				j := (^Print_Job)(user)
				s := pdf.shown_size(j.pages[page])
				return {f64(s.x), f64(s.y)}
			},
			render = proc(user: rawptr, page: int, size: [2]int, rows: [2]int, out: []u8) -> bool {
				j := (^Print_Job)(user)
				if j.cached != page || j.cached_size != size {
					delete(j.pixels)
					j.pixels = pdf.render(j.pages[page], size.x, size.y, j.layer)
					j.cached, j.cached_size = page, size
				}
				if j.pixels == nil { return false }
				from, to := rows[0] * size.x * 4, rows[1] * size.x * 4
				if from < 0 || to > len(j.pixels) || to - from != len(out) { return false }
				copy(out, j.pixels[from:to])
				return true
			},
		}
		j.status = platform.print_document(j.window, doc)
		p := new(Printed)
		p^ = {status = j.status, user = j.user}
		if !ui.post(j.state, j.done, p) { free(p) }
		print_job_free(j)
	}, j)
}

@(private = "file")
print_job_free :: proc(j: ^Print_Job) {
	for p in j.pages { stamps_free(p.stamps) }
	delete(j.pages)
	delete(j.file)
	delete(j.title)
	delete(j.pixels)
	free(j)
}
