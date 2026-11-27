package feuille

// The preview thread of the signature (src/md/features/signature.md, The preview thread): a pool of one, apart from
// the document's worker. It gives the engine the script fonts once, then, for the newest ask only, composes the
// signature's marks, renders them on white and posts the marks, their size and the picture. Every engine call of the
// signature runs here: the interface's thread asks and reads the answers.

import "base:runtime"
import "core:math"
import "core:sync"
import pdf "gt:pdf"
import "gt:tasks"
import "gt:ui"

// The room around the marks in the picture, in points: the flourish and the tilt never touch its edge.
SIGN_PREVIEW_MARGIN :: 4

// What the thread posts: the engine's ids of the fonts, then each preview.
Sign_Answers :: struct {
	state:   ^ui.State,
	user:    rawptr,
	faces:   ui.Post_Proc,   // data: ^Sign_Faces
	preview: ui.Post_Proc,   // data: ^Sign_Preview
	linear:  bool,           // the renderer's textures are premultiplied in linear light (render.blend_space)
}

Sign_Faces :: struct {
	faces: [Script]pdf.Face,
	ok:    bool,
	user:  rawptr,
}

// A preview: the marks composed for ask `serial` (owned), the picture of their box and margin (`px` pixels, RGBA:
// nil when there is nothing to place). A drawn signature's pad too: its finished strokes' ink, `pad_px` pixels for the
// pad's units (nil: none asked, or no stroke), `pad_strokes` of them, for the pad's `epoch` (signature_view.odin).
Sign_Preview :: struct {
	serial:      u64,
	marks:       Sign_Marks,
	rgba:        []u8,
	px:          [2]int,
	px_per_pt:   f32,      // the pixels a point of `px` (the preview's zoom asks a finer one)
	pad_rgba:    []u8,
	pad_px:      [2]int,
	pad_strokes: int,
	epoch:       u64,
	user:        rawptr,
}

sign_preview_free :: proc(p: ^Sign_Preview) {
	sign_marks_free(&p.marks)
	delete(p.rgba)
	delete(p.pad_rgba)
	free(p)
}

Sign_Thread :: struct {
	answers:   Sign_Answers,
	pool:      tasks.Pool,
	job:       tasks.Job,
	lock:      sync.Mutex,
	allocator: runtime.Allocator,
	// under `lock`: the newest ask
	asked:     bool,
	serial:    u64,
	sig:       Signature,     // owned
	px_per_pt: f32,
	pad_px:    [2]int,
	epoch:     u64,
	// the thread's own
	faces:     [Script]pdf.Face,
	fonts:     bool,          // given to the engine
}

sign_thread_start :: proc(t: ^Sign_Thread, answers: Sign_Answers) {
	t.answers = answers
	t.allocator = runtime.heap_allocator()
	t.job = {work = sign_run, data = t}
	tasks.start(&t.pool, {threads = 1})
	// (the fonts at once: the tool waits for their ids)
	tasks.job_ask(&t.pool, &t.job)
}

sign_thread_stop :: proc(t: ^Sign_Thread) {
	context.allocator = t.allocator
	tasks.stop(&t.pool)
	signature_free(&t.sig)
}

// Asks for the preview of `s` (copied), `px_per_pt` pixels a point, and its pad's ink at `pad_px` pixels ({}: none)
// for the pad's `epoch`; it replaces an ask still waiting.
sign_thread_ask :: proc(t: ^Sign_Thread, serial: u64, s: Signature, px_per_pt: f32, pad_px: [2]int, epoch: u64) {
	context.allocator = t.allocator
	sync.guard(&t.lock)
	signature_free(&t.sig)
	t.sig = signature_clone(s)
	t.serial, t.px_per_pt, t.pad_px, t.epoch, t.asked = serial, px_per_pt, pad_px, epoch, true
	tasks.job_ask(&t.pool, &t.job)
}

@(private = "file")
sign_run :: proc(data: rawptr) {
	t := (^Sign_Thread)(data)
	context.allocator = t.allocator
	if !t.fonts {
		t.fonts = true
		f := new(Sign_Faces)
		f.ok, f.user = pdf.available(), t.answers.user
		for script, k in SCRIPTS {
			face, ok := pdf.font_add(script.data)
			f.faces[k] = face
			f.ok &&= ok
		}
		t.faces = f.faces
		if !ui.post(t.answers.state, t.answers.faces, f) { free(f) }
	}
	sync.lock(&t.lock)
	asked, serial, sig, px, pad_px, epoch := t.asked, t.serial, t.sig, t.px_per_pt, t.pad_px, t.epoch
	t.asked, t.sig = false, {}
	sync.unlock(&t.lock)
	if !asked { return }
	defer signature_free(&sig)
	linear := t.answers.linear
	p := new(Sign_Preview)
	p.serial, p.epoch, p.user, p.px_per_pt = serial, epoch, t.answers.user, px
	// (the pad's finished strokes, as the engine lays them: gt:draw's polygon fill is not made for a grained ink's
	// hundreds of pieces; the stroke under way the pad draws itself)
	if sig.mode == .Drawn && len(sig.strokes) > 0 && pad_px.x > 0 && pad_px.y > 0 {
		shapes := make([dynamic]pdf.Shape, context.temp_allocator)
		c := sig.ink
		for st in sig.strokes {
			for l in stroke_levels(sig, st, context.temp_allocator) {
				if len(l.points) == 0 { continue }
				a := u8(clamp(math.round(l.alpha * 255), 1, 255))
				append(&shapes, pdf.Shape{kind = .Outline, points = level_points(l, 1, {}, context.temp_allocator), fill = {c[0], c[1], c[2], a}})
			}
		}
		p.pad_rgba = pdf.render({size = SIGN_PAD, shapes = shapes[:]}, pad_px.x, pad_px.y)
		if p.pad_rgba != nil {
			ink_alone(p.pad_rgba, sig.ink, linear)
			p.pad_px, p.pad_strokes = pad_px, len(sig.strokes)
		}
	}
	p.marks = sign_compose(sig, t.faces)
	if size := p.marks.size; size.x > 0 && size.y > 0 {
		page := sign_preview_page(p.marks, context.temp_allocator)
		p.px = {max(int(math.ceil(page.size.x * px)), 1), max(int(math.ceil(page.size.y * px)), 1)}
		p.rgba = pdf.render(page, p.px.x, p.px.y)
		if p.rgba == nil { p.px = {} } else { ink_alone(p.rgba, sig.ink, linear) }
	}
	if !ui.post(t.answers.state, t.answers.preview, p) { sign_preview_free(p) }
}

// The picture's white made transparent: every mark of a signature is in its one ink, so a pixel's darkness is how
// much ink covers it. Premultiplied, as the renderer's textures are (`linear`: in linear light, the renderer's
// default blend space; else on sRGB values): over the dialog's paper it is the picture again, over a page the words
// under it stay seen.
//
// The engine composes a translucent ink on sRGB values; mixed in linear light with the same alpha it comes out
// lighter (84 % blue over white: 65 against 115 in red). In linear light the alpha is the one that gives the engine's
// darkness over white, on the ink's darkest channel; the others follow its colour.
ink_alone :: proc(rgba: []u8, c: [3]u8, linear: bool) {
	decode :: proc(x: f32) -> f32 { return x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4) }
	encode :: proc(x: f32) -> f32 { return x <= 0.0031308 ? x * 12.92 : 1.055 * math.pow(x, 1 / 2.4) - 0.055 }
	dark := min(c[0], c[1], c[2])
	// (a pixel's darkest channel says it all: one entry for each of its 256 values)
	table: [256][4]u8
	for v in 0 ..< 256 {
		a: f32
		if linear {
			room := 1 - decode(f32(dark) / 255)
			a = room > 1e-4 ? clamp((1 - decode(f32(v) / 255)) / room, 0, 1) : 0
		} else {
			room := 255 - f32(dark)
			a = room >= 1 ? clamp((255 - f32(v)) / room, 0, 1) : 0
		}
		for ch in 0 ..< 3 {
			x := f32(c[ch]) / 255
			table[v][ch] = u8(clamp((linear ? encode(decode(x) * a) : x * a) * 255 + 0.5, 0, 255))
		}
		table[v][3] = u8(a * 255 + 0.5)
	}
	for i := 0; i + 3 < len(rgba); i += 4 {
		t := table[min(rgba[i], rgba[i + 1], rgba[i + 2])]
		rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3] = t[0], t[1], t[2], t[3]
	}
}

// A blank page holding the marks with their margin (the marks' strings and points shared, the lists `allocator`'s).
sign_preview_page :: proc(m: Sign_Marks, allocator := context.temp_allocator) -> pdf.Page {
	off := [2]f32{SIGN_PREVIEW_MARGIN, SIGN_PREVIEW_MARGIN}
	stamps := make([]pdf.Stamp, len(m.stamps), allocator)
	for s, i in m.stamps {
		stamps[i] = s
		stamps[i].at += off
	}
	shapes := make([]pdf.Shape, len(m.shapes), allocator)
	for s, i in m.shapes {
		shapes[i] = s
		shapes[i].points = make([][2]f32, len(s.points), allocator)
		for q, k in s.points { shapes[i].points[k] = q + off }
	}
	return {size = m.size + 2 * off, stamps = stamps, shapes = shapes}
}
