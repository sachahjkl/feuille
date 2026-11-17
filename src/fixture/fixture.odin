// The tests' PDF writer: the documents the tests open are written here, never kept as binary files in the repository.
// The engine's public API cannot make an encrypted file or a widget's appearance, so the writer makes them: pages with a
// blue base rectangle, on the first page (`layer`) a text field with a red appearance, a signature widget with a green
// one and a text annotation, and the standard security handler's RC4 40-bit encryption with a user password. Only the
// test files import this package. src/md/features/masked-opening.md.
package fixture

import "core:crypto/legacy/md5"
import "core:fmt"
import "core:strings"

// A page: its size in points, its /Rotate in degrees.
Page :: struct {
	size:   [2]f32,
	rotate: int,
}

Options :: struct {
	pages:    []Page,   // nil: one page of 200 x 200
	layer:    bool,     // the field, the signature and the annotation on the first page
	password: string,   // "": not encrypted
}

// Where the first page's parts are, in points from its bottom left corner (PDF's y goes up).
BASE_RECT      :: [4]f32{20, 150, 160, 30}   // x, y, width, height: blue, every page
FIELD_RECT     :: [4]f32{20, 20, 140, 30}    // red, the text field's appearance
SIGNATURE_RECT :: [4]f32{20, 60, 140, 30}    // green, the signature's appearance
NOTE_RECT      :: [4]f32{170, 170, 20, 20}   // the text annotation

// The standard padding of the security handler.
@(private)
PAD :: [32]u8{
	0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
	0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
}

@(private)
ID :: "feuille-fixture!"

// The document, in `allocator`.
make_pdf :: proc(o: Options, allocator := context.allocator) -> []u8 {
	pages := o.pages
	if len(pages) == 0 { pages = []Page{{size = {200, 200}}} }
	w := Writer{encrypted = o.password != ""}
	w.buf = make([dynamic]u8, allocator)
	w.offsets = make([dynamic]int, context.temp_allocator)

	o_key, u_key: [32]u8
	if w.encrypted { o_key, u_key, w.file_key = keys(o.password) }

	// objects: 1 catalog, 2 page tree, 3 the field, 4 the signature, 5 the annotation, 6 and 7 their appearances,
	// 8 the encryption, then two per page (the page and its content)
	first_page := 9
	kids := strings.builder_make(context.temp_allocator)
	for _, i in pages { fmt.sbprintf(&kids, "%d 0 R ", first_page + 2 * i) }

	text(&w, "%PDF-1.4\n")
	fields := o.layer ? "/AcroForm << /Fields [3 0 R 4 0 R] >>" : ""
	object(&w, 1, fmt.tprintf("<< /Type /Catalog /Pages 2 0 R %s >>", fields))
	object(&w, 2, fmt.tprintf("<< /Type /Pages /Kids [%s] /Count %d >>", strings.to_string(kids), len(pages)))
	object(&w, 3, fmt.tprintf("<< /Type /Annot /Subtype /Widget /FT /Tx /T %s /F 4 /Rect %s /AP << /N 6 0 R >> /P %d 0 R >>", literal(&w, 3, "name"), rect(FIELD_RECT), first_page))
	object(&w, 4, fmt.tprintf("<< /Type /Annot /Subtype /Widget /FT /Sig /T %s /F 4 /Rect %s /AP << /N 7 0 R >> /P %d 0 R >>", literal(&w, 4, "signature"), rect(SIGNATURE_RECT), first_page))
	object(&w, 5, fmt.tprintf("<< /Type /Annot /Subtype /Text /F 4 /Rect %s /Contents %s >>", rect(NOTE_RECT), literal(&w, 5, "a note")))
	stream(&w, 6, fmt.tprintf("/Type /XObject /Subtype /Form /BBox [0 0 %v %v]", FIELD_RECT[2], FIELD_RECT[3]), fmt.tprintf("1 0 0 rg 0 0 %v %v re f", FIELD_RECT[2], FIELD_RECT[3]))
	stream(&w, 7, fmt.tprintf("/Type /XObject /Subtype /Form /BBox [0 0 %v %v]", SIGNATURE_RECT[2], SIGNATURE_RECT[3]), fmt.tprintf("0 1 0 rg 0 0 %v %v re f", SIGNATURE_RECT[2], SIGNATURE_RECT[3]))
	if w.encrypted {
		object(&w, 8, fmt.tprintf("<< /Filter /Standard /V 1 /R 2 /O <%s> /U <%s> /P -4 >>", hex(o_key[:]), hex(u_key[:])))
	} else {
		object(&w, 8, "null")
	}
	for p, i in pages {
		n := first_page + 2 * i
		annots := o.layer && i == 0 ? "/Annots [3 0 R 4 0 R 5 0 R]" : ""
		object(&w, n, fmt.tprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %v %v] /Rotate %d /Resources << >> /Contents %d 0 R %s >>", p.size.x, p.size.y, p.rotate, n + 1, annots))
		stream(&w, n + 1, "", fmt.tprintf("0 0 1 rg %v re f", rect_box(BASE_RECT)))
	}

	xref := len(w.buf)
	count := len(w.offsets)
	text(&w, fmt.tprintf("xref\n0 %d\n0000000000 65535 f \n", count))
	for n in 1 ..< count { text(&w, fmt.tprintf("%010d 00000 n \n", w.offsets[n])) }
	encrypt := w.encrypted ? "/Encrypt 8 0 R" : ""
	text(&w, fmt.tprintf("trailer\n<< /Size %d /Root 1 0 R /ID [<%s> <%s>] %s >>\nstartxref\n%d\n%%%%EOF\n", count, hex(transmute([]u8)string(ID)), hex(transmute([]u8)string(ID)), encrypt, xref))
	return w.buf[:]
}

@(private)
Writer :: struct {
	buf:       [dynamic]u8,
	offsets:   [dynamic]int,   // by object number; 0 unused
	encrypted: bool,
	file_key:  [5]u8,
}

@(private)
text :: proc(w: ^Writer, s: string) { append(&w.buf, s) }

@(private)
object :: proc(w: ^Writer, n: int, body: string) {
	mark(w, n)
	text(w, fmt.tprintf("%d 0 obj\n%s\nendobj\n", n, body))
}

@(private)
stream :: proc(w: ^Writer, n: int, dict: string, data: string) {
	mark(w, n)
	bytes := crypt(w, n, transmute([]u8)data)
	text(w, fmt.tprintf("%d 0 obj\n<< /Length %d %s >>\nstream\n", n, len(bytes), dict))
	append(&w.buf, ..bytes)
	text(w, "\nendstream\nendobj\n")
}

@(private)
mark :: proc(w: ^Writer, n: int) {
	for len(w.offsets) <= n { append(&w.offsets, 0) }
	w.offsets[n] = len(w.buf)
}

// A string of object `n`, as the file writes it (hex; encrypted when the file is).
@(private)
literal :: proc(w: ^Writer, n: int, s: string) -> string {
	return fmt.tprintf("<%s>", hex(crypt(w, n, transmute([]u8)s)))
}

@(private)
rect :: proc(r: [4]f32) -> string { return fmt.tprintf("[%v %v %v %v]", r[0], r[1], r[0] + r[2], r[1] + r[3]) }

@(private)
rect_box :: proc(r: [4]f32) -> string { return fmt.tprintf("%v %v %v %v", r[0], r[1], r[2], r[3]) }

@(private)
hex :: proc(data: []u8) -> string {
	b := strings.builder_make(context.temp_allocator)
	for v in data { fmt.sbprintf(&b, "%02x", v) }
	return strings.to_string(b)
}

@(private)
md5_of :: proc(parts: ..[]u8) -> (sum: [16]u8) {
	ctx: md5.Context
	md5.init(&ctx)
	for p in parts { md5.update(&ctx, p) }
	md5.final(&ctx, sum[:])
	return
}

@(private)
rc4 :: proc(key, data: []u8) -> []u8 {
	s: [256]u8
	for i in 0 ..< 256 { s[i] = u8(i) }
	j: u8
	for i in 0 ..< 256 {
		j += s[i] + key[i % len(key)]
		s[i], s[j] = s[j], s[i]
	}
	out := make([]u8, len(data), context.temp_allocator)
	x, y: u8
	for k in 0 ..< len(data) {
		x += 1
		y += s[x]
		s[x], s[y] = s[y], s[x]
		out[k] = data[k] ~ s[s[x] + s[y]]
	}
	return out
}

// The bytes of object `n` as the file stores them: the object's key is the file key and the object's number, hashed
// (the handler's algorithm 1, revision 2: 5 + 5 bytes).
@(private)
crypt :: proc(w: ^Writer, n: int, data: []u8) -> []u8 {
	if !w.encrypted { return data }
	tail := [5]u8{u8(n), u8(n >> 8), u8(n >> 16), 0, 0}
	key := md5_of(w.file_key[:], tail[:])
	return rc4(key[:10], data)
}

// /O, /U and the file key of revision 2, with no owner password and /P -4 (algorithms 2, 3 and 4). With no owner
// password, algorithm 3 takes the user's in its place.
@(private)
keys :: proc(password: string) -> (o, u: [32]u8, file_key: [5]u8) {
	padded :: proc(s: string) -> (out: [32]u8) {
		out = PAD
		n := copy(out[:], s)
		pad := PAD
		copy(out[n:], pad[:])
		return
	}
	owner, user := padded(password), padded(password)
	owner_key := md5_of(owner[:])
	copy(o[:], rc4(owner_key[:5], user[:]))
	p := [4]u8{0xFC, 0xFF, 0xFF, 0xFF}   // (-4, little-endian)
	id := ID
	key := md5_of(user[:], o[:], p[:], transmute([]u8)id)
	copy(file_key[:], key[:5])
	pad := PAD
	copy(u[:], rc4(file_key[:], pad[:]))
	return
}
