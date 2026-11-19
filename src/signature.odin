package feuille

// The signature (src/md/features/signature.md): what the person composes, typed in a script font or drawn with a
// pen's ink, kept in signature.txt of the state folder; and its marks, composed in points by the preview thread
// (signature_thread.odin), placed in one edit. The dialog and the pad are signature_view.odin.

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:time"
import i18n "gt:i18n"
import ink "gt:ink"
import pdf "gt:pdf"
import "gt:platform"
import store "gt:store"
import "gt:timefmt"

// The script fonts a typed signature takes (assets/fonts, their licences beside them). `scale`: the size of a name
// in it against SIGN_TYPED_PT, so the five look alike in size (their x-heights differ by half).
Script :: enum u8 { Delafield, Muellerhoff, Alex_Brush, Sacramento, Homemade_Apple }

Script_Font :: struct {
	name:  string,
	data:  []u8,
	scale: f32,
}

SCRIPTS := [Script]Script_Font{
	.Delafield      = {name = "Mrs Saint Delafield", data = #load("../assets/fonts/MrsSaintDelafield-Regular.ttf"), scale = 1.35},
	.Muellerhoff    = {name = "Herr Von Muellerhoff", data = #load("../assets/fonts/HerrVonMuellerhoff-Regular.ttf"), scale = 1.3},
	.Alex_Brush     = {name = "Alex Brush", data = #load("../assets/fonts/AlexBrush-Regular.ttf"), scale = 1.0},
	.Sacramento     = {name = "Sacramento", data = #load("../assets/fonts/Sacramento-Regular.ttf"), scale = 1.15},
	.Homemade_Apple = {name = "Homemade Apple", data = #load("../assets/fonts/HomemadeApple-Regular.ttf"), scale = 0.8},
}

// The two ways of a signature: its tabs.
Sign_Mode :: enum u8 { Typed, Drawn }

// The nibs of the pad (gt:ink's presets).
Pen_Kind :: enum u8 { Ballpoint, Fountain, Felt, Brush }

PENS := [Pen_Kind]ink.Pen{
	.Ballpoint = ink.PEN_BALLPOINT,
	.Fountain  = ink.PEN_FOUNTAIN,
	.Felt      = ink.PEN_FELT,
	.Brush     = ink.PEN_BRUSH,
}

// The pad's units: its width and height. A stroke's samples are in them, and the pens' widths too.
SIGN_PAD :: [2]f32{600, 200}
// gt:ink's presets are widths for a screen's pixels; the pad is a signature's room, drawn larger than it is placed:
// at the thickness 1, a fountain pen's full width is 6.6 units (2 points placed), its hairline under 1.
SIGN_PEN_K :: 2.2

// The pen of the pad: its nib's preset at the thickness chosen.
sign_pen :: proc(s: Signature) -> ink.Pen {
	return ink.scaled(PENS[s.pen], s.thickness * SIGN_PEN_K)
}
// A typed name's size at the size slider's 1, in points; a drawing's points per unit of the pad at 1 (the whole pad
// is 180 points wide: 63 mm).
SIGN_TYPED_PT :: 30
SIGN_POINTS_PER_UNIT :: 0.3
// The mention's size against the name's, the caption's size in points at 1, the room between the parts in points.
SIGN_MENTION_K :: 0.55
SIGN_CAPTION_PT :: 9
SIGN_GAP_PT :: 2
// The ink's colours: black, a blue, a dark blue.
SIGN_INKS := [?][3]u8{{20, 20, 24}, {29, 64, 175}, {23, 37, 84}}

// A stroke of the pad: the pointer's samples, in the pad's units, its time from the stroke's start.
Stroke :: [dynamic]ink.Sample

// What the person composed. The strings and the strokes are owned (signature_free).
Signature :: struct {
	mode:      Sign_Mode,
	name:      string,
	script:    Script,
	ink:       [3]u8,
	tilt:      f32,      // degrees, rising to the right
	weight:    f32,      // the pen's weight, thousandths of the size
	flourish:  bool,
	mention:   bool,     // "Read and approved" above it
	dated:     bool,     // the line of the place and the date under it
	place:     string,
	date:      string,   // not kept: today at each start
	scale:     f32,      // the size slider: 0.5 .. 2
	pen:       Pen_Kind,
	thickness: f32,      // the pen's width against its preset's: 0.5 .. 2.5
	strokes:   [dynamic]Stroke,
}

SIGNATURE_DEFAULT :: Signature{mode = .Typed, script = .Delafield, ink = {29, 64, 175}, tilt = 4, weight = 20, flourish = true, scale = 1, pen = .Fountain, thickness = 1.2}

signature_free :: proc(s: ^Signature) {
	delete(s.name)
	delete(s.place)
	delete(s.date)
	for st in s.strokes { delete(st) }
	delete(s.strokes)
	s^ = {}
}

signature_clone :: proc(s: Signature, allocator := context.allocator) -> Signature {
	out := s
	out.name = strings.clone(s.name, allocator)
	out.place = strings.clone(s.place, allocator)
	out.date = strings.clone(s.date, allocator)
	out.strokes = make([dynamic]Stroke, 0, len(s.strokes), allocator)
	for st in s.strokes {
		c := make(Stroke, len(st), allocator)
		copy(c[:], st[:])
		append(&out.strokes, c)
	}
	return out
}

// Whether it has something to place: a name, or a stroke.
signature_ready :: proc(s: Signature) -> bool {
	return s.mode == .Typed ? strings.trim_space(s.name) != "" : len(s.strokes) > 0
}

// Today, as the caption writes it.
signature_today :: proc(allocator := context.allocator) -> string {
	// (the local clock: UTC moved by the zone's offset, read as UTC)
	t := time.time_add(time.now(), time.Duration(timefmt.local_offset_minutes()) * time.Minute)
	y, m, d := time.date(t)
	return fmt.aprintf(i18n.tr("%02d/%02d/%d"), d, int(m), y, allocator = allocator)
}

// The line under the signature: the place and the date, or the date alone.
signature_caption :: proc(s: Signature, allocator := context.temp_allocator) -> string {
	if !s.dated { return "" }
	place, date := strings.trim_space(s.place), strings.trim_space(s.date)
	switch {
	case place != "" && date != "": return fmt.aprintf(i18n.tr("Done at %s, on %s"), place, date, allocator = allocator)
	case place != "":              return fmt.aprintf(i18n.tr("Done at %s"), place, allocator = allocator)
	case date != "":               return fmt.aprintf(i18n.tr("On %s"), date, allocator = allocator)
	}
	return ""
}

////////////////////////////////
// What is kept

signature_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/signature.txt"}, allocator)
}

// The signature kept (the defaults when none); the date is today.
signature_load :: proc(st: ^store.Store, allocator := context.allocator) -> Signature {
	s := SIGNATURE_DEFAULT
	context.allocator = allocator
	get :: proc(st: ^store.Store, key: string) -> (string, bool) { return store.get(st, key) }
	num :: proc(st: ^store.Store, key: string, lo, hi, fallback: f32) -> f32 {
		v, ok := store.get(st, key)
		if !ok { return fallback }
		f, parsed := strconv.parse_f32(v)
		return parsed && !math.is_nan(f) ? clamp(f, lo, hi) : fallback
	}
	flag :: proc(st: ^store.Store, key: string, fallback: bool) -> bool {
		v, ok := store.get(st, key)
		return ok ? v == "1" : fallback
	}
	if v, ok := get(st, "mode"); ok && v == "drawn" { s.mode = .Drawn }
	if v, ok := get(st, "name"); ok { s.name = strings.clone(v) }
	if v, ok := get(st, "place"); ok { s.place = strings.clone(v) }
	if v, ok := get(st, "script"); ok {
		for f, k in SCRIPTS { if f.name == v { s.script = k } }
	}
	if v, ok := get(st, "pen"); ok {
		for k in Pen_Kind { if fmt.tprint(k) == v { s.pen = k } }
	}
	if v, ok := get(st, "ink"); ok {
		n, parsed := strconv.parse_int(v, 16)
		if parsed { s.ink = {u8(n >> 16), u8(n >> 8), u8(n)} }
	}
	s.tilt = num(st, "tilt", -15, 15, s.tilt)
	s.weight = num(st, "weight", 0, 80, s.weight)
	s.scale = num(st, "scale", 0.5, 2, s.scale)
	s.thickness = num(st, "thickness", 0.5, 2.5, s.thickness)
	s.flourish = flag(st, "flourish", s.flourish)
	s.mention = flag(st, "mention", s.mention)
	s.dated = flag(st, "dated", s.dated)
	s.strokes = make([dynamic]Stroke)
	if v, ok := get(st, "strokes"); ok { strokes_parse(v, &s.strokes) }
	s.date = signature_today()
	return s
}

// The signature written to its store (its worker writes the file).
signature_keep :: proc(st: ^store.Store, s: Signature) {
	f :: proc(v: f32) -> string { return fmt.tprintf("%.2f", v) }
	b :: proc(v: bool) -> string { return v ? "1" : "0" }
	entries := [?]store.Entry{
		{"mode", s.mode == .Drawn ? "drawn" : "typed"},
		{"name", one_line(s.name)},
		{"script", SCRIPTS[s.script].name},
		{"ink", fmt.tprintf("%02x%02x%02x", s.ink[0], s.ink[1], s.ink[2])},
		{"tilt", f(s.tilt)},
		{"weight", f(s.weight)},
		{"flourish", b(s.flourish)},
		{"mention", b(s.mention)},
		{"dated", b(s.dated)},
		{"place", one_line(s.place)},
		{"scale", f(s.scale)},
		{"pen", fmt.tprint(s.pen)},
		{"thickness", f(s.thickness)},
		{"strokes", strokes_format(s.strokes[:])},
	}
	store.replace(st, entries[:])
}

// (the store's lines are tab-separated, one a line)
@(private = "file")
one_line :: proc(s: string) -> string {
	out, _ := strings.replace_all(s, "\t", " ", context.temp_allocator)
	out, _ = strings.replace_all(out, "\n", " ", context.temp_allocator)
	return out
}

// The strokes as text: "x,y,t" samples (tenths of a unit, milliseconds) joined by ";", the strokes by "|".
strokes_format :: proc(strokes: []Stroke, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for st, i in strokes {
		if i > 0 { strings.write_byte(&b, '|') }
		for p, k in st {
			if k > 0 { strings.write_byte(&b, ';') }
			fmt.sbprintf(&b, "%d,%d,%d", int(math.round(p.at.x * 10)), int(math.round(p.at.y * 10)), int(math.round(p.time)))
		}
	}
	return strings.to_string(b)
}

// The strokes of strokes_format's text added to `out`; a sample that does not read is skipped.
strokes_parse :: proc(text: string, out: ^[dynamic]Stroke) {
	rest := text
	for part in strings.split_iterator(&rest, "|") {
		st := make(Stroke)
		samples := part
		for one in strings.split_iterator(&samples, ";") {
			fields := strings.split(one, ",", context.temp_allocator)
			if len(fields) != 3 { continue }
			x, ok1 := strconv.parse_int(fields[0])
			y, ok2 := strconv.parse_int(fields[1])
			t, ok3 := strconv.parse_int(fields[2])
			if !ok1 || !ok2 || !ok3 { continue }
			append(&st, ink.Sample{at = {f32(x) / 10, f32(y) / 10}, time = f64(t)})
		}
		if len(st) > 0 { append(out, st) } else { delete(st) }
	}
}

////////////////////////////////
// The marks

// The marks of a signature in points, upright, their box's top-left corner at 0, 0: what the preview shows and a
// click places. The strings and points are owned (sign_marks_free).
Sign_Marks :: struct {
	stamps: []pdf.Stamp,
	shapes: []pdf.Shape,
	size:   [2]f32,
}

sign_marks_free :: proc(m: ^Sign_Marks, allocator := context.allocator) {
	for s in m.stamps {
		delete(s.text, allocator)
		delete(s.caption, allocator)
	}
	delete(m.stamps, allocator)
	for s in m.shapes { delete(s.points, allocator) }
	delete(m.shapes, allocator)
	m^ = {}
}

sign_marks_clone :: proc(m: Sign_Marks, allocator := context.allocator) -> Sign_Marks {
	out := m
	out.stamps = make([]pdf.Stamp, len(m.stamps), allocator)
	for s, i in m.stamps {
		out.stamps[i] = s
		out.stamps[i].text = strings.clone(s.text, allocator)
		out.stamps[i].caption = strings.clone(s.caption, allocator)
	}
	out.shapes = make([]pdf.Shape, len(m.shapes), allocator)
	for s, i in m.shapes {
		out.shapes[i] = s
		out.shapes[i].points = make([][2]f32, len(s.points), allocator)
		copy(out.shapes[i].points, s.points)
	}
	return out
}

// The ink of the strokes as one Outline shape, in the pad's units (NaN between the contours), and its box.
sign_ink :: proc(s: Signature, allocator := context.allocator) -> (points: [dynamic][2]f32, lo, hi: [2]f32) {
	points = make([dynamic][2]f32, allocator)
	lo, hi = {max(f32), max(f32)}, {min(f32), min(f32)}
	pen := sign_pen(s)
	for st in s.strokes {
		o := ink.outline(st[:], pen, context.temp_allocator)
		poly := ink.polygon(o, context.temp_allocator)
		if len(poly) < 3 { continue }
		if len(points) > 0 { append(&points, [2]f32{math.nan_f32(), math.nan_f32()}) }
		for q in poly {
			append(&points, q)
			lo, hi = {min(lo.x, q.x), min(lo.y, q.y)}, {max(hi.x, q.x), max(hi.y, q.y)}
		}
	}
	return
}

// The marks of `s` with the engine's fonts `faces` (the preview thread: pdf.stamp_size is the engine's). Empty when
// there is nothing to place.
sign_compose :: proc(s: Signature, faces: [Script]pdf.Face, allocator := context.allocator) -> (m: Sign_Marks) {
	if !signature_ready(s) { return }
	context.allocator = allocator
	color := s.ink
	face := faces[s.script]
	scale := clamp(s.scale, 0.5, 2)
	caption := signature_caption(s)
	mention := i18n.tr("Read and approved")
	name_pt := SIGN_TYPED_PT * scale * SCRIPTS[s.script].scale
	stamps := make([dynamic]pdf.Stamp)
	shapes := make([dynamic]pdf.Shape)
	switch s.mode {
	case .Typed:
		text := strings.trim_space(s.name)
		// (the mention is a line of the same hand above the name: one stamp, one mark)
		if s.mention { text = fmt.tprintf("%s\n%s", mention, text) }
		st := pdf.Stamp{face = face, size = name_pt, color = color, text = strings.clone(text), tilt = s.tilt, weight = s.weight, flourish = s.flourish, caption = strings.clone(caption)}
		m.size = pdf.stamp_size(st)
		append(&stamps, st)
	case .Drawn:
		raw, lo, hi := sign_ink(s, context.temp_allocator)
		if len(raw) == 0 { return }
		k := SIGN_POINTS_PER_UNIT * scale
		y: f32 = 0
		w := (hi.x - lo.x) * k
		if s.mention {
			st := pdf.Stamp{face = face, size = name_pt * SIGN_MENTION_K, color = color, text = strings.clone(mention)}
			wh := pdf.stamp_size(st)
			append(&stamps, st)
			y += wh.y + SIGN_GAP_PT
			w = max(w, wh.x)
		}
		points := make([][2]f32, len(raw))
		for q, i in raw { points[i] = math.is_nan(q.x) ? q : (q - lo) * k + {0, y} }
		append(&shapes, pdf.Shape{kind = .Outline, points = points, fill = {color[0], color[1], color[2], 255}})
		y += (hi.y - lo.y) * k
		if caption != "" {
			st := pdf.Stamp{at = {0, y + SIGN_GAP_PT}, font = {family = .Sans}, size = max(SIGN_CAPTION_PT * scale, 7), color = color, text = strings.clone(caption)}
			wh := pdf.stamp_size(st)
			append(&stamps, st)
			y += SIGN_GAP_PT + wh.y
			w = max(w, wh.x)
		}
		m.size = {w, y}
	}
	m.stamps, m.shapes = stamps[:], shapes[:]
	return
}
