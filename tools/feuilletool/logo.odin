package feuilletool

// logo: feuille's mark, drawn by the toolkit's paint package (the same bytes on every system). An autumn maple leaf in
// flight: five rounded lobes with a few teeth, tilted and a little narrowed as if it turned in the air, warm from a
// golden tip to a red base, darker on one side of the midrib (the leaf is creased), its veins painted in a pale gold,
// its stem behind it. Nothing is cut out and nothing is outlined: the mark reads the same on a light and on a dark
// background. Small sizes drop the veins (detail_for). toolbox.write_logo writes assets/logo*.png, feuille.ico and
// .project/image.png from logo_draw.

import "core:math"
import paint "gt:paint"
import toolbox "gt:toolbox"

LOGO_DIR       :: "assets"
LOGO_MASTER    :: 1024
LOGO_SIZES     :: [?]int{16, 32, 64, 128, 256}
LOGO_ICO       :: "assets/feuille.ico"
// The drawing's own units: a square of LOGO_UNITS, scaled to the canvas.
LOGO_UNITS     :: 512.0
// The least width a size is drawn at before the toolbox shrinks it.
LOGO_DRAW_SIZE :: 512
// The room left between the mark and the square's edge, on its widest side, in units.
LOGO_MARGIN    :: 10.0

// The flight: the leaf narrowed across and turned; logo_draw then fits it to the square.
FLIGHT_NARROW :: 0.92
FLIGHT_TURN   :: -20.0 / 360   // turns

// The colours: the golden tip, the orange middle, the red base, the crease's shade, the veins, the stem.
LEAF_TIP    :: 0xFFC53D
LEAF_MIDDLE :: 0xF5761A
LEAF_BASE   :: 0xC92A1C
CREASE      :: 0x6B1306
VEIN        :: 0xFFE7B0
STEM        :: 0x8E3412

// A lobe: its direction (degrees from up, clockwise) and its length from the stem's join, in units.
Lobe :: struct {
	angle, length: f32,
}

LOBES :: [5]Lobe{{-106, 142}, {-52, 192}, {0, 214}, {52, 192}, {106, 142}}
// The bottom of the notch between two neighbouring lobes, from the join.
SINUS_DEEP :: 86.0
SINUS_LOW  :: 66.0

// A point of the outline: a sharp one is a corner (a tooth, a tip); a soft one bends the outline through it.
@(private = "file")
Point :: struct {
	at:    [2]f32,
	sharp: bool,
}

@(private = "file")
toward :: proc(degrees, r: f32) -> [2]f32 {
	a := math.to_radians(degrees)
	return {r * math.sin(a), -r * math.cos(a)}
}

// The outline in the leaf's own frame (the stem's join at 0,0, the top lobe up), clockwise from the top tip.
@(private = "file")
outline :: proc() -> [dynamic]Point {
	points := make([dynamic]Point, context.temp_allocator)
	lobes := LOBES
	lobe :: proc(points: ^[dynamic]Point, l: Lobe) {
		a := math.to_radians(l.angle)
		along := [2]f32{math.sin(a), -math.cos(a)}
		across := [2]f32{math.cos(a), math.sin(a)}   // (clockwise)
		at :: proc(along, across: [2]f32, l: Lobe, u, v: f32) -> [2]f32 { return along * (u * l.length) + across * (v * l.length) }
		append(points,
			Point{at(along, across, l, 0.46, -0.31), true},    // the tooth before
			Point{at(along, across, l, 0.60, -0.17), false},
			Point{at(along, across, l, 0.74, -0.16), true},    // a small tooth near the tip
			Point{at(along, across, l, 0.84, -0.07), false},
			Point{at(along, across, l, 1.00, 0), true},        // the tip
			Point{at(along, across, l, 0.84, 0.07), false},
			Point{at(along, across, l, 0.74, 0.16), true},
			Point{at(along, across, l, 0.60, 0.17), false},
			Point{at(along, across, l, 0.46, 0.31), true},     // the tooth after
		)
	}
	// from the top tip: its right half, then each lobe clockwise with the notch before it, then the left half of the top
	top := lobes[2]
	append(&points, Point{toward(top.angle, top.length), true})
	lobe_half := make([dynamic]Point, context.temp_allocator)
	lobe(&lobe_half, top)
	for p in lobe_half[5:] { append(&points, p) }
	append(&points, Point{toward(26, SINUS_DEEP), false})
	lobe(&points, lobes[3])
	append(&points, Point{toward(78, SINUS_LOW), false})
	lobe(&points, lobes[4])
	// the base: round under the lower lobes, a small notch where the stem joins
	append(&points, Point{toward(140, 52), false}, Point{{0, 22}, false}, Point{toward(-140, 52), false})
	lobe(&points, lobes[0])
	append(&points, Point{toward(-78, SINUS_LOW), false})
	lobe(&points, lobes[1])
	append(&points, Point{toward(-26, SINUS_DEEP), false})
	for p in lobe_half[:4] { append(&points, p) }
	return points
}

// The outline as a path: straight into each corner, a curve through each soft point (from the middle of its sides).
@(private = "file")
outline_path :: proc(p: ^paint.Path, points: []Point) {
	n := len(points)
	paint.move_to(p, points[0].at.x, points[0].at.y)
	for i := 1; i <= n; {
		q := points[i % n]
		if q.sharp {
			paint.line_to(p, q.at.x, q.at.y)
			i += 1
			continue
		}
		next := points[(i + 1) % n]
		if next.sharp {
			paint.quad_to(p, q.at.x, q.at.y, next.at.x, next.at.y)
			i += 2
		} else {
			mid := (q.at + next.at) * 0.5
			paint.quad_to(p, q.at.x, q.at.y, mid.x, mid.y)
			i += 1
		}
	}
	paint.close(p)
}

// A vein: a thin wedge from `from` to `to`, `base` wide at its start and `tip` at its end.
@(private = "file")
vein :: proc(p: ^paint.Path, from, to: [2]f32, base, tip: f32) {
	d := to - from
	n := [2]f32{-d.y, d.x} / math.sqrt(d.x * d.x + d.y * d.y)
	paint.start_figure(p)
	paint.move_to(p, from.x + n.x * base / 2, from.y + n.y * base / 2)
	paint.line_to(p, to.x + n.x * tip / 2, to.y + n.y * tip / 2)
	paint.line_to(p, to.x - n.x * tip / 2, to.y - n.y * tip / 2)
	paint.line_to(p, from.x - n.x * base / 2, from.y - n.y * base / 2)
	paint.close(p)
}

// 2: everything (64 px and up); 1: the main veins, wider (32 to 48); 0: no vein (16 to 24).
detail_for :: proc(size: int) -> int { return size <= 24 ? 0 : size <= 48 ? 1 : 2 }

// The picture `pixels` wide, with the detail it keeps once shrunk to `size`.
logo_draw :: proc(pixels, size: int) -> paint.Canvas {
	detail := detail_for(size)
	c := paint.canvas_make(pixels, pixels)
	k := f32(pixels) / LOGO_UNITS

	// the leaf's frame placed in the square: narrowed, turned, moved (a call's step applies before the steps already in
	// the matrix, so they are written last step first)
	flight := paint.rotate_at(paint.IDENTITY, FLIGHT_TURN, 0, 0)
	flight = paint.scale(flight, FLIGHT_NARROW, 1)
	place :: proc(m: paint.Matrix, p: [2]f32) -> [2]f32 { return paint.apply(m, p) }

	// the whole mark as large as the square holds, LOGO_MARGIN from its widest side: a taskbar or a dock shows an icon
	// in a fixed square, and a mark that leaves it empty around looks smaller than its neighbours
	lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{min(f32), min(f32)}
	grow :: proc(lo, hi: ^[2]f32, p: [2]f32, r: f32 = 0) {
		lo^ = {min(lo.x, p.x - r), min(lo.y, p.y - r)}
		hi^ = {max(hi.x, p.x + r), max(hi.y, p.y + r)}
	}
	for p in outline() { grow(&lo, &hi, place(flight, p.at)) }
	stem_width: f32 = detail == 0 ? 20 : 14
	for p in ([3][2]f32{{0, 0}, {-4, 70}, {22, 128}}) { grow(&lo, &hi, place(flight, p), stem_width / 2) }
	fit := (LOGO_UNITS - 2 * LOGO_MARGIN) / max(hi.x - lo.x, hi.y - lo.y)
	centre := (lo + hi) * 0.5
	c.transform = paint.scale(paint.IDENTITY, k, k)
	c.transform = paint.translate(c.transform, LOGO_UNITS / 2, LOGO_UNITS / 2)
	c.transform = paint.scale(c.transform, fit, fit)
	c.transform = paint.translate(c.transform, -centre.x, -centre.y)

	// the stem, behind the leaf: a slight curve down from the join
	stem: paint.Path
	defer paint.path_destroy(&stem)
	paint.move_to(&stem, 0, 0)
	paint.quad_to(&stem, -4, 70, 22, 128)
	paint.path_transform(&stem, flight)
	paint.stroke(&c, stem, {width = stem_width, cap = .Round}, paint.solid(paint.hex(STEM)))

	// the leaf, warm from its tip to its base
	leaf: paint.Path
	defer paint.path_destroy(&leaf)
	points := outline()
	outline_path(&leaf, points[:])
	paint.path_transform(&leaf, flight)
	lobes := LOBES
	face := paint.linear(place(flight, toward(0, lobes[2].length)), place(flight, {0, 40}), {}, {})
	paint.set_stops(&face, {{0, paint.hex(LEAF_TIP)}, {0.5, paint.hex(LEAF_MIDDLE)}, {1, paint.hex(LEAF_BASE)}})
	paint.fill(&c, leaf, face)

	// the crease: the half right of the midrib a shade darker, fading away from the midrib
	paint.set_clip(&c, leaf)
	half: paint.Path
	defer paint.path_destroy(&half)
	paint.polygon(&half, {{0, -300}, {300, -300}, {300, 200}, {0, 200}})
	paint.path_transform(&half, flight)
	paint.fill(&c, half, paint.linear(place(flight, {0, 0}), place(flight, {200, 0}), paint.hex(CREASE, 70), paint.hex(CREASE, 25)))
	paint.reset_clip(&c)

	// the veins: the midrib and one to each lobe, from the join to near the tips
	if detail >= 1 {
		veins: paint.Path
		defer paint.path_destroy(&veins)
		wide: f32 = detail == 1 ? 1.8 : 1
		for l in lobes {
			main_base: f32 = l.angle == 0 ? 11 : 9
			vein(&veins, {0, 8}, toward(l.angle, l.length * 0.86), main_base * wide, 2 * wide)
		}
		if detail >= 2 {
			// the side veins of the three upper lobes, toward their first teeth
			for l in lobes[1:4] {
				a := math.to_radians(l.angle)
				along := [2]f32{math.sin(a), -math.cos(a)}
				across := [2]f32{math.cos(a), math.sin(a)}
				from := along * (0.30 * l.length)
				for side in ([2]f32{-1, 1}) {
					vein(&veins, from, along * (0.50 * l.length) + across * (side * 0.24 * l.length), 4.5, 1.5)
				}
			}
		}
		paint.path_transform(&veins, flight)
		paint.set_clip(&c, leaf)
		paint.fill(&c, veins, paint.solid(paint.hex(VEIN, detail == 1 ? 150 : 175)))
		paint.reset_clip(&c)
	}
	return c
}

// The files of the logo (the `logo` command): assets/logo*.png, feuille.ico and .project/image.png.
logo :: proc() -> toolbox.Logo {
	@(static) sizes := LOGO_SIZES
	return {
		draw = proc(pixels, size: int, _: rawptr) -> paint.Canvas { return logo_draw(pixels, size) },
		draw_size = LOGO_DRAW_SIZE,
		dir = LOGO_DIR, master = LOGO_MASTER, sizes = sizes[:], ico = LOGO_ICO, project_image = true,
	}
}
