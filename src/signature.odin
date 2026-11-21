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
import "gt:turn"

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

// The language a signature's words are written in: the document's, whatever the program's. A contract in English is
// signed "Read and approved" in a French Feuille.
Sign_Lang :: enum u8 { French, English, German, Spanish, Italian, Portuguese, Dutch }

// A language's words for a signature: their usual turns, not word-for-word translations. `place_date` takes the place
// then the date; `months` empty: a numeric date, its parts joined by `date_sep`.
Sign_Words :: struct {
	tag:        string,   // its BCP 47 tag's language, as the program's language is named (i18n)
	name:       string,   // the language in itself: the menu shows it so
	mention:    string,
	place_date: string,
	place_only: string,
	date_only:  string,
	months:     [12]string,
	date_sep:   string,
}

SIGN_WORDS := [Sign_Lang]Sign_Words{
	.French     = {tag = "fr", name = "Français", mention = "Lu et approuvé", place_date = "Fait à %s, le %s", place_only = "Fait à %s", date_only = "Le %s", date_sep = "/"},
	.English    = {tag = "en", name = "English", mention = "Read and approved", place_date = "Done at %s, on %s", place_only = "Done at %s", date_only = "On %s",
		months = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}},
	.German     = {tag = "de", name = "Deutsch", mention = "Gelesen und genehmigt", place_date = "%s, den %s", place_only = "%s", date_only = "Den %s", date_sep = "."},
	.Spanish    = {tag = "es", name = "Español", mention = "Leído y aprobado", place_date = "En %s, a %s", place_only = "En %s", date_only = "A %s", date_sep = "/"},
	.Italian    = {tag = "it", name = "Italiano", mention = "Letto e approvato", place_date = "%s, lì %s", place_only = "%s", date_only = "Lì %s", date_sep = "/"},
	.Portuguese = {tag = "pt", name = "Português", mention = "Lido e aprovado", place_date = "%s, %s", place_only = "%s", date_only = "%s", date_sep = "/"},
	.Dutch      = {tag = "nl", name = "Nederlands", mention = "Gelezen en goedgekeurd", place_date = "Opgemaakt te %s op %s", place_only = "Opgemaakt te %s", date_only = "Op %s", date_sep = "-"},
}

// A new signature's language: the program's when a signature can be written in it, else English.
sign_lang_default :: proc() -> Sign_Lang {
	tag := ""
	if l := i18n.current(); l != nil { tag = l.tag }
	for w, k in SIGN_WORDS {
		if strings.has_prefix(tag, w.tag) && (len(tag) == len(w.tag) || tag[len(w.tag)] == '-') { return k }
	}
	return .English
}

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
	lang:      Sign_Lang, // the mention's and the caption's
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

// A day as `lang` writes it on a document: "21/11/2026", "21 November 2026", "21.11.2026".
sign_date :: proc(lang: Sign_Lang, y, m, d: int, allocator := context.allocator) -> string {
	w := SIGN_WORDS[lang]
	if w.months[0] != "" { return fmt.aprintf("%d %s %d", d, w.months[clamp(m, 1, 12) - 1], y, allocator = allocator) }
	return fmt.aprintf("%02d%s%02d%s%d", d, w.date_sep, m, w.date_sep, y, allocator = allocator)
}

// Today, as the caption writes it in `lang`.
signature_today :: proc(lang: Sign_Lang, allocator := context.allocator) -> string {
	// (the local clock: UTC moved by the zone's offset, read as UTC)
	t := time.time_add(time.now(), time.Duration(timefmt.local_offset_minutes()) * time.Minute)
	y, m, d := time.date(t)
	return sign_date(lang, y, int(m), d, allocator)
}

// The line under the signature, in its language: the place and the date, or one of them.
signature_caption :: proc(s: Signature, allocator := context.temp_allocator) -> string {
	if !s.dated { return "" }
	w := SIGN_WORDS[s.lang]
	place, date := strings.trim_space(s.place), strings.trim_space(s.date)
	switch {
	case place != "" && date != "": return fmt.aprintf(w.place_date, place, date, allocator = allocator)
	case place != "":              return fmt.aprintf(w.place_only, place, allocator = allocator)
	case date != "":               return fmt.aprintf(w.date_only, date, allocator = allocator)
	}
	return ""
}

////////////////////////////////
// What is kept

signatures_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/signatures.txt"}, allocator)
}

// The first line of an exported file, and its extension.
SIGNATURES_HEADER :: "feuille signatures 1"
SIGNATURES_EXT :: "signatures"

// A signature's fields, as the store and the exported file write them (no prefix; one line each).
signature_fields :: proc(s: Signature, allocator := context.temp_allocator) -> [15]store.Entry {
	context.allocator = allocator
	f :: proc(v: f32) -> string { return fmt.aprintf("%.2f", v) }
	b :: proc(v: bool) -> string { return v ? "1" : "0" }
	return {
		{"mode", s.mode == .Drawn ? "drawn" : "typed"},
		{"name", one_line(s.name)},
		{"script", SCRIPTS[s.script].name},
		{"ink", fmt.aprintf("%02x%02x%02x", s.ink[0], s.ink[1], s.ink[2])},
		{"tilt", f(s.tilt)},
		{"weight", f(s.weight)},
		{"flourish", b(s.flourish)},
		{"mention", b(s.mention)},
		{"dated", b(s.dated)},
		{"place", one_line(s.place)},
		{"lang", SIGN_WORDS[s.lang].tag},
		{"scale", f(s.scale)},
		{"pen", fmt.aprint(s.pen)},
		{"thickness", f(s.thickness)},
		{"strokes", strokes_format(s.strokes[:], allocator)},
	}
}

// What tells two signatures apart: their fields as one text (an import adds no signature already kept).
signature_key :: proc(s: Signature, allocator := context.temp_allocator) -> string {
	fields := signature_fields(s)
	b := strings.builder_make(allocator)
	for e in fields { fmt.sbprintf(&b, "%s\t%s\n", e.key, e.value) }
	return strings.to_string(b)
}

// Signature `n` of `fields` (keys "<n>.<field>"); ok false when there is none. Its date is today.
signature_read :: proc(fields: map[string]string, n: int, allocator := context.allocator) -> (s: Signature, ok: bool) {
	get :: proc(fields: map[string]string, n: int, key: string) -> (string, bool) { return fields[fmt.tprintf("%d.%s", n, key)] }
	mode := get(fields, n, "mode") or_return
	context.allocator = allocator
	s = SIGNATURE_DEFAULT
	num :: proc(fields: map[string]string, n: int, key: string, lo, hi, fallback: f32) -> f32 {
		v, ok := get(fields, n, key)
		if !ok { return fallback }
		f, parsed := strconv.parse_f32(v)
		return parsed && !math.is_nan(f) ? clamp(f, lo, hi) : fallback
	}
	flag :: proc(fields: map[string]string, n: int, key: string, fallback: bool) -> bool {
		v, ok := get(fields, n, key)
		return ok ? v == "1" : fallback
	}
	if mode == "drawn" { s.mode = .Drawn }
	if v, has := get(fields, n, "name"); has { s.name = strings.clone(v) }
	if v, has := get(fields, n, "place"); has { s.place = strings.clone(v) }
	if v, has := get(fields, n, "script"); has {
		for f, k in SCRIPTS { if f.name == v { s.script = k } }
	}
	if v, has := get(fields, n, "pen"); has {
		for k in Pen_Kind { if fmt.tprint(k) == v { s.pen = k } }
	}
	s.lang = sign_lang_default()
	if v, has := get(fields, n, "lang"); has {
		for w, k in SIGN_WORDS { if w.tag == v { s.lang = k } }
	}
	if v, has := get(fields, n, "ink"); has {
		c, parsed := strconv.parse_int(v, 16)
		if parsed { s.ink = {u8(c >> 16), u8(c >> 8), u8(c)} }
	}
	s.tilt = num(fields, n, "tilt", -15, 15, s.tilt)
	s.weight = num(fields, n, "weight", 0, 80, s.weight)
	s.scale = num(fields, n, "scale", 0.5, 2, s.scale)
	s.thickness = num(fields, n, "thickness", 0.5, 2.5, s.thickness)
	s.flourish = flag(fields, n, "flourish", s.flourish)
	s.mention = flag(fields, n, "mention", s.mention)
	s.dated = flag(fields, n, "dated", s.dated)
	s.strokes = make([dynamic]Stroke)
	if v, has := get(fields, n, "strokes"); has { strokes_parse(v, &s.strokes) }
	s.date = signature_today(s.lang)
	return s, true
}

// The signatures of `fields`, from 0 until the first number missing.
signatures_read :: proc(fields: map[string]string, allocator := context.allocator) -> [dynamic]Signature {
	out := make([dynamic]Signature, allocator)
	for n := 0; ; n += 1 {
		s, ok := signature_read(fields, n, allocator)
		if !ok { break }
		append(&out, s)
	}
	return out
}

// Every field of `list`, numbered: the store's entries.
signatures_entries :: proc(list: []Signature, allocator := context.temp_allocator) -> [dynamic]store.Entry {
	out := make([dynamic]store.Entry, 0, len(list) * 15 + 1, allocator)
	for s, n in list {
		for e in signature_fields(s, allocator) { append(&out, store.Entry{fmt.aprintf("%d.%s", n, e.key, allocator = allocator), e.value}) }
	}
	return out
}

// The exported file's text: its header, then one field a line.
signatures_text :: proc(list: []Signature, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, SIGNATURES_HEADER)
	strings.write_byte(&b, '\n')
	for e in signatures_entries(list) { fmt.sbprintf(&b, "%s\t%s\n", e.key, e.value) }
	return strings.to_string(b)
}

// The signatures of an exported file's text; ok false when it is not one (its header).
signatures_parse :: proc(text: string, allocator := context.allocator) -> (list: [dynamic]Signature, ok: bool) {
	rest := text
	first, _ := strings.split_lines_iterator(&rest)
	if strings.trim_space(first) != SIGNATURES_HEADER { return }
	fields := make(map[string]string, 64, context.temp_allocator)
	for line in strings.split_lines_iterator(&rest) {
		tab := strings.index_byte(line, '\t')
		if tab < 0 { continue }
		fields[line[:tab]] = strings.trim_right(line[tab + 1:], "\r")
	}
	return signatures_read(fields, allocator), true
}

// The library kept in its store, and which one is chosen; one signature, the defaults, when it holds none.
signatures_load :: proc(st: ^store.Store, allocator := context.allocator) -> (list: [dynamic]Signature, chosen: int) {
	fields := make(map[string]string, 64, context.temp_allocator)
	for e in store.list(st) { fields[e.key] = e.value }
	list = signatures_read(fields, allocator)
	if len(list) == 0 {
		s := SIGNATURE_DEFAULT
		s.strokes = make([dynamic]Stroke, allocator)
		s.lang = sign_lang_default()
		s.date = signature_today(s.lang, allocator)
		append(&list, s)
	}
	if v, ok := fields["chosen"]; ok {
		n, _ := strconv.parse_int(v)
		chosen = clamp(n, 0, len(list) - 1)
	}
	return
}

// The library written to its store (its worker writes the file).
signatures_keep :: proc(st: ^store.Store, list: []Signature, chosen: int) {
	entries := signatures_entries(list)
	append(&entries, store.Entry{"chosen", fmt.tprintf("%d", chosen)})
	store.replace(st, entries[:])
}

// (the store's lines are tab-separated, one a line)
@(private = "file")
one_line :: proc(s: string) -> string {
	out, _ := strings.replace_all(s, "\t", " ", context.temp_allocator)
	out, _ = strings.replace_all(out, "\n", " ", context.temp_allocator)
	return out
}

// The strokes as text: "x,y,t" samples (tenths of a unit, milliseconds), ",p" after them when a stylus measured a
// pressure (thousandths), and ",tx,ty" after that when it leaned (tenths of a degree), joined by ";", the strokes by
// "|".
strokes_format :: proc(strokes: []Stroke, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for st, i in strokes {
		if i > 0 { strings.write_byte(&b, '|') }
		for p, k in st {
			if k > 0 { strings.write_byte(&b, ';') }
			fmt.sbprintf(&b, "%d,%d,%d", int(math.round(p.at.x * 10)), int(math.round(p.at.y * 10)), int(math.round(p.time)))
			leaned := p.tilt != {}
			if p.pressure > 0 || leaned { fmt.sbprintf(&b, ",%d", int(math.round(p.pressure * 1000))) }
			// (the file keeps tenths of a degree, as before: a sample's tilt is turns only in memory)
			if leaned { fmt.sbprintf(&b, ",%d,%d", int(math.round(turn.to_degrees(p.tilt.x) * 10)), int(math.round(turn.to_degrees(p.tilt.y) * 10))) }
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
			if len(fields) != 3 && len(fields) != 4 && len(fields) != 6 { continue }
			x, ok1 := strconv.parse_int(fields[0])
			y, ok2 := strconv.parse_int(fields[1])
			t, ok3 := strconv.parse_int(fields[2])
			if !ok1 || !ok2 || !ok3 { continue }
			pressure: f32
			tilt: [2]f32
			if len(fields) >= 4 {
				p, okp := strconv.parse_int(fields[3])
				if !okp { continue }
				pressure = clamp(f32(p) / 1000, 0, 1)
			}
			if len(fields) == 6 {
				tx, okx := strconv.parse_int(fields[4])
				ty, oky := strconv.parse_int(fields[5])
				if !okx || !oky { continue }
				tilt = {turn.from_degrees(clamp(f32(tx) / 10, -90, 90)), turn.from_degrees(clamp(f32(ty) / 10, -90, 90))}
			}
			append(&st, ink.Sample{at = {f32(x) / 10, f32(y) / 10}, time = f64(t), pressure = pressure, tilt = tilt})
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

// The levels a stroke's ink is drawn in (gt:ink's cumulative fills): the pad and the PDF draw the same ones.
SIGN_LEVELS :: 6

// A stroke's seed: from its first sample, so its ink is the same at every render, while it is being drawn too, and
// whatever strokes come before it or are removed.
stroke_seed :: proc(st: Stroke) -> u32 {
	if len(st) == 0 { return 1 }
	h := u32(i32(st[0].at.x * 10)) * 2654435761 ~ u32(i32(st[0].at.y * 10)) * 2246822519
	return h | 1
}

// A stroke's ink as levels, in the pad's units: each level one fill of its alpha. The levels are `allocator`'s.
stroke_levels :: proc(s: Signature, st: Stroke, allocator := context.allocator) -> []ink.Level {
	laid := ink.lay(st[:], sign_pen(s), stroke_seed(st), context.temp_allocator)
	return ink.levels(laid, SIGN_LEVELS, allocator)
}

// One level as an Outline's points: its contours, a NaN point between two; each point through `to`.
level_points :: proc(l: ink.Level, k: f32, origin: [2]f32, allocator := context.allocator) -> [][2]f32 {
	n := len(l.points) + max(len(l.contours) - 1, 0)
	out := make([][2]f32, n, allocator)
	i := 0
	for c, ci in l.contours {
		if ci > 0 {
			out[i] = {math.nan_f32(), math.nan_f32()}
			i += 1
		}
		for q in c {
			out[i] = (q - origin) * k
			i += 1
		}
	}
	return out
}

// The ink of the strokes as shapes in points (`k` points a unit), its box's corner at 0, `y` down from the top: one
// Outline a level of each stroke, so two strokes that cross lay two layers of ink. ok false: no ink at all.
sign_ink_shapes :: proc(s: Signature, k, y: f32, allocator := context.allocator) -> (shapes: [dynamic]pdf.Shape, size: [2]f32, ok: bool) {
	per := make([dynamic][]ink.Level, context.temp_allocator)
	lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
	for st in s.strokes {
		ls := stroke_levels(s, st, context.temp_allocator)
		append(&per, ls)
		for l in ls {
			for q in l.points { lo, hi = {min(lo.x, q.x), min(lo.y, q.y)}, {max(hi.x, q.x), max(hi.y, q.y)} }
		}
	}
	if lo.x > hi.x { return }
	shapes = make([dynamic]pdf.Shape, allocator)
	c := s.ink
	for ls in per {
		for l in ls {
			if len(l.points) == 0 { continue }
			pts := level_points(l, k, lo, allocator)
			for &q in pts { q.y += y }
			a := u8(clamp(math.round(l.alpha * 255), 1, 255))
			append(&shapes, pdf.Shape{kind = .Outline, points = pts, fill = {c[0], c[1], c[2], a}})
		}
	}
	return shapes, (hi - lo) * k, true
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
	mention := SIGN_WORDS[s.lang].mention
	name_pt := SIGN_TYPED_PT * scale * SCRIPTS[s.script].scale
	stamps := make([dynamic]pdf.Stamp)
	shapes := make([dynamic]pdf.Shape)
	switch s.mode {
	case .Typed:
		text := strings.trim_space(s.name)
		// (the mention is a line of the same hand above the name: one stamp, one mark)
		if s.mention { text = fmt.tprintf("%s\n%s", mention, text) }
		st := pdf.Stamp{face = face, size = name_pt, color = color, text = strings.clone(text), tilt = turn.from_degrees(s.tilt), weight = s.weight, flourish = s.flourish, caption = strings.clone(caption)}
		m.size = pdf.stamp_size(st)
		append(&stamps, st)
	case .Drawn:
		k := SIGN_POINTS_PER_UNIT * scale
		y: f32 = 0
		w: f32 = 0
		if s.mention {
			st := pdf.Stamp{face = face, size = name_pt * SIGN_MENTION_K, color = color, text = strings.clone(mention)}
			wh := pdf.stamp_size(st)
			append(&stamps, st)
			y += wh.y + SIGN_GAP_PT
			w = max(w, wh.x)
		}
		inked, size, ok := sign_ink_shapes(s, k, y)
		if !ok {
			for st in stamps { delete(st.text) }
			delete(stamps)
			delete(shapes)
			return
		}
		append(&shapes, ..inked[:])
		delete(inked)
		w = max(w, size.x)
		y += size.y
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
