package fixture

// A document that looks like the ones feuille is for: an A4 application form in two pages, its text in the standard
// Helvetica, its fields and its signature box as widgets with appearances, a reviewer's sticky note. The README's and
// the site's pictures show it (app_test.odin's pictures), masked and with its layer.

import "core:fmt"
import "core:strings"

@(private = "file")
A4 :: [2]f32{595, 842}

// A widget of the sample: its rectangle (x, y, width, height), its kind, its words.
@(private = "file")
Sample_Field :: struct {
	rect:      [4]f32,
	signature: bool,
	words:     string,
}

@(private = "file")
SAMPLE_FIELDS := [?]Sample_Field{
	{{150, 618, 380, 22}, false, "Jane Doe"},
	{{150, 588, 380, 22}, false, "12 Elm Street, Springfield"},
	{{150, 558, 130, 22}, false, "2026-11-17"},
	{{340, 558, 190, 22}, false, "FR76 3000 6000 0112"},
	{{64, 120, 230, 70}, true, "Sign here"},
}

// The text of a page: its lines at their places, in the regular face (F1) or the bold one (F2).
@(private = "file")
Line :: struct {
	at:   [2]f32,
	bold: bool,
	size: f32,
	text: string,
}

@(private = "file")
PAGE_ONE := [?]Line{
	{{64, 760}, true, 20, "Application for reimbursement"},
	{{64, 738}, false, 10, "Form A-112 - Department of Public Services - Please complete every section."},
	{{64, 690}, true, 12, "1. Applicant"},
	{{64, 624}, false, 10, "Full name"},
	{{64, 594}, false, 10, "Address"},
	{{64, 564}, false, 10, "Date"},
	{{300, 564}, false, 10, "IBAN"},
	{{64, 510}, true, 12, "2. Statement"},
	{{64, 488}, false, 10, "I declare that the expenses listed in the attached schedule were incurred in the course"},
	{{64, 474}, false, 10, "of my duties, that they have not been reimbursed by any other body, and that the"},
	{{64, 460}, false, 10, "receipts joined to this application are complete and genuine. I understand that any"},
	{{64, 446}, false, 10, "false statement may lead to the refusal of this application and to proceedings."},
	{{64, 400}, true, 12, "3. Schedule of expenses"},
	{{64, 376}, false, 10, "Travel                                                                              312.40"},
	{{64, 360}, false, 10, "Accommodation                                                                   268.00"},
	{{64, 344}, false, 10, "Meals                                                                                 94.15"},
	{{64, 322}, true, 10, "Total                                                                                674.55"},
	{{64, 210}, true, 12, "4. Signature"},
	{{64, 196}, false, 10, "Signed and dated by the applicant."},
	{{64, 60}, false, 8, "Page 1 of 2"},
}

@(private = "file")
PAGE_TWO := [?]Line{
	{{64, 760}, true, 16, "Notes for applicants"},
	{{64, 730}, false, 10, "Applications are processed in the order they arrive. Allow four weeks for a decision."},
	{{64, 714}, false, 10, "Join one receipt for each line of the schedule; a copy is enough when the original is lost,"},
	{{64, 698}, false, 10, "provided that it is legible. Amounts are in euros, taxes included."},
	{{64, 660}, true, 12, "Where to send this form"},
	{{64, 640}, false, 10, "Department of Public Services, Reimbursements, 1 Civic Square, Springfield."},
	{{64, 60}, false, 8, "Page 2 of 2"},
}

// The sample, in `allocator`.
make_sample :: proc(allocator := context.allocator) -> []u8 {
	w := Writer{}
	w.buf = make([dynamic]u8, allocator)
	w.offsets = make([dynamic]int, context.temp_allocator)
	fields := SAMPLE_FIELDS
	// 1 catalog, 2 pages, 3 and 4 the faces, 5..8 page one and its content, page two and its content, then for each
	// field its widget and its appearance, then the note
	first_field := 9
	note := first_field + 2 * len(fields)
	widgets := strings.builder_make(context.temp_allocator)
	for _, i in fields { fmt.sbprintf(&widgets, "%d 0 R ", first_field + 2 * i) }

	text(&w, "%PDF-1.7\n")
	object(&w, 1, fmt.tprintf("<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [%s] /DR << /Font << /F1 3 0 R >> >> >> >>", strings.to_string(widgets)))
	object(&w, 2, "<< /Type /Pages /Kids [5 0 R 7 0 R] /Count 2 >>")
	object(&w, 3, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
	object(&w, 4, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
	resources := "/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >>"
	object(&w, 5, fmt.tprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %v %v] %s /Contents 6 0 R /Annots [%s%d 0 R] >>", A4.x, A4.y, resources, strings.to_string(widgets), note))
	stream(&w, 6, "", page_content(PAGE_ONE[:], true))
	object(&w, 7, fmt.tprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %v %v] %s /Contents 8 0 R >>", A4.x, A4.y, resources))
	stream(&w, 8, "", page_content(PAGE_TWO[:], false))
	for f, i in fields {
		n := first_field + 2 * i
		kind := f.signature ? "/FT /Sig" : "/FT /Tx"
		object(&w, n, fmt.tprintf("<< /Type /Annot /Subtype /Widget %s /T (field%d) /F 4 /Rect %s /P 5 0 R /AP << /N %d 0 R >> >>", kind, i, rect(f.rect), n + 1))
		stream(&w, n + 1, fmt.tprintf("/Type /XObject /Subtype /Form /BBox [0 0 %v %v] /Resources << /Font << /F1 3 0 R >> >>", f.rect[2], f.rect[3]), field_look(f))
	}
	object(&w, note, "<< /Type /Annot /Subtype /Text /F 4 /Rect [538 558 560 580] /Open false /C [1 0.85 0.2] /Contents (Check the IBAN before filing.) >>")

	xref := len(w.buf)
	count := len(w.offsets)
	text(&w, fmt.tprintf("xref\n0 %d\n0000000000 65535 f \n", count))
	for n in 1 ..< count { text(&w, fmt.tprintf("%010d 00000 n \n", w.offsets[n])) }
	text(&w, fmt.tprintf("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", count, xref))
	return w.buf[:]
}

// A page's content: its lines, and on page one the rules under the field labels and the boxes of the schedule.
@(private = "file")
page_content :: proc(lines: []Line, rules: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	if rules {
		// the label's lines and a soft box around the statement
		strings.write_string(&b, "0.75 G 0.6 w\n")
		for y in ([?]f32{614, 584, 554}) { fmt.sbprintf(&b, "150 %v m 530 %v l S\n", y, y) }
		strings.write_string(&b, "0.96 0.96 0.97 rg 58 436 474 66 re f\n")
		strings.write_string(&b, "0.3 G 1 w 64 336 m 530 336 l S\n")
		strings.write_string(&b, "0.2 0.35 0.6 RG 2 w 64 704 m 530 704 l S\n")
	}
	strings.write_string(&b, "0.1 g\n")
	for l in lines {
		face := l.bold ? "/F2" : "/F1"
		fmt.sbprintf(&b, "BT %s %v Tf %v %v Td (%s) Tj ET\n", face, l.size, l.at.x, l.at.y, l.text)
	}
	return strings.to_string(b)
}

// What a filled field looks like in Acrobat: a pale blue box with the words; the signature box a yellow band with its
// call to sign.
@(private = "file")
field_look :: proc(f: Sample_Field) -> string {
	w, h := f.rect[2], f.rect[3]
	if f.signature {
		return fmt.tprintf("1 0.93 0.55 rg 0 0 %v %v re f 0.85 0.6 0.1 RG 1.5 w 0.75 0.75 %v %v re S BT /F1 14 Tf 0.45 0.3 0 rg 12 %v Td (%s) Tj ET", w, h, w - 1.5, h - 1.5, h / 2 - 5, f.words)
	}
	return fmt.tprintf("0.8 0.87 1 rg 0 0 %v %v re f 0.45 0.55 0.85 RG 1 w 0.5 0.5 %v %v re S BT /F1 11 Tf 0 0 0.3 rg 6 %v Td (%s) Tj ET", w, h, w - 1, h - 1, h / 2 - 4, f.words)
}
