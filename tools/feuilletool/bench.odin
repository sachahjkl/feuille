package feuilletool

// bench: PDFium and hayro (a renderer in pure Rust) on the same hard PDFs, to decide whether hayro can become a backend
// of the toolkit (ROADMAP.md). The corpus: files of pdf.js's test suite at a pinned commit, each checked by its SHA-256
// (downloaded into build/, never kept in the repository), and the tests' own documents (the sample form, an encrypted
// one). Each page is rendered by both at the same size, on white; the report says what opened, what failed, how long a
// page took, and how far the pictures are apart. hayro runs in a program of its own (tools/bench/hayro), one process per
// file under `timeout`: a hang or a crash is a result, not the end of the bench.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"
import cli "gt:cli"
import toolbox "gt:toolbox"
import fixture "../../src/fixture"
import pdf "../../src/pdf"

BENCH_DIR      :: "build/bench"
BENCH_SCALE    :: 1.5      // pixels per point (108 dpi)
BENCH_TIMEOUT  :: "120"    // seconds a file may take in hayro
// A pixel differs when one of its channels is this far apart: below, anti-aliasing and rounding.
BENCH_DIFF_MIN :: 48
PDFJS_COMMIT   :: "03ed8399ed85fd3bb0656fe567710fd4a7c2a294"

@(rodata)
BENCH_CORPUS := [?][2]string{
	{"160F-2019.pdf", "f41f0818365ffd14ca4e55c0556355193bd76632b970d60cc2dec554cac6f379"},
	{"alphatrans.pdf", "234c0ab8e9458f4d17133b08d2b66170eeb92be2a80e1508aa5117a2bf568f63"},
	{"annotation-text-widget.pdf", "9f091ceb368ad0406094efaa6c50d5033735ee52f383e0973dc53a7467089d7c"},
	{"annotation-tx2.pdf", "9612df43f8c48b574ddc7a81c0781b864235f7ff328dc9b9e646b924a8706650"},
	{"annotation-button-widget.pdf", "f7b1c9c7b2ecb909f6b168cc1b137230076533f977a205472b212b7f0d3a78d7"},
	{"annotation-choice-widget.pdf", "2fcab2aed82afe9775359c1d166fb7aae77e99d25fe03be177e233d02d572538"},
	{"form_two_pages.pdf", "6d7c608d0102fa1e1b3cbc2c3b0a989783e90f84ff1a7fe7cbdb6dc2a1b60fbd"},
	{"bug1947248_forms.pdf", "3b7ac84716ce403f1502c7c4c7878e61e36970dff3cb3ffa4fb78e2eefeb75c1"},
	{"file_pdfjs_form.pdf", "808af1e794952475e8af824ad1ee6ac41d6646de122e5ac91975e75b0951c80b"},
	{"checkbox-bad-appearance.pdf", "0cd13bf7375a2b6b9b01bb694aefcfe9dac225105cb9ad7e03798783b3318ad9"},
	{"annotation-stamp.pdf", "76d566c092c23ccbec4bb488c40dc6daec8a381cb5386452b186728652436704"},
	{"annotation-freetext.pdf", "318ed4bead93fa6ff023571b17ddca41e82fe2347b497ea24903a11e1892fb71"},
	{"annotation-highlight.pdf", "72b6387356ccfdfb95a0a5eff5e1ceb9b7667019807d7b04abaf64dad7ea143a"},
	{"ArabicCIDTrueType.pdf", "1cad1de912ba29f89a6d8b08bc5b0f84382874ffedab2c8f9e05ef608c265bb1"},
	{"arial_unicode_ab_cidfont.pdf", "049a4330710d8470896061acf7ee486735e94cef2769f6cc13fec3cb13bb65aa"},
	{"complex_ttf_font.pdf", "4b205d3fd11e7ad2b9b86cc446561909d48dd9e0b38327cfd69d0fdeb6c28e14"},
	{"TrueType_without_cmap.pdf", "3e111eef52ce9c0d0b1da043290df4b49a5670c89891fcb3db6962edb12e35aa"},
	{"Type3WordSpacing.pdf", "8ac40dc49d40af8b5a50b442ced56b8db962c961a779a0284cd3a6207adc0bb7"},
	{"ContentStreamCycleType3insideType3.pdf", "131aec277c444c985d502e5f589f37735d275a8ea247c1beedba0781fbe99d40"},
	{"blendmode.pdf", "39ce34c2d32738c7c94970fd76559ecb9efd671f5ab99e515a853674e7a824ce"},
	{"cmykjpeg.pdf", "659d6b19912f63db988b0b26b9bde0e6d8100667ef162051a4a84ea8e5b90272"},
	{"devicen.pdf", "1fbaf094e1c714513aea19258e74269b6b5365ea769e288a8e142773f6cf2b94"},
	{"function_based_shading.pdf", "21a0d4951f2d45f86d90dd9bac824805b54b2bd2fefe6efad763d227d484ed64"},
	{"axial_shading_many_inputs.pdf", "4d86a414969c1c849e6866193c2c41653463d694a02ffc91b0ba663a7d107ee8"},
	{"ShowText-ShadingPattern.pdf", "13ac785e8445fbf01d5a8200e0e899daa204cdbe723b02f38f8af61ac48707bb"},
	{"ccitt_EndOfBlock_false.pdf", "f2289b94e7e3f05f9e37754c399d3f525edf9444fb32c3279959cf64b575fe62"},
	{"hello_world_rotated.pdf", "ab0cb700cd5e5338fd676dfca25becae800acd2be03a4e57856485b8cfd2d28b"},
	{"helloworld-bad.pdf", "c3e22ea5d7e6f5b7218d76abce4284728889df516a93c1b74a82c4fd69aa1639"},
	{"bad-PageLabels.pdf", "eff0ee7d1cf2e1a7ccfb25a8fc4c2bbea0ec23c838b61a199a57dbb732ddeaad"},
	{"asciihexdecode.pdf", "17cc92aa58ec48f75b01c6b6e7f8c8bade0a36f7295d0f833a16bafae854dc79"},
	{"TAMReview.pdf", "a6db6d2f5e4f97e1e28a5919a875a40b89e38d0229b33cc023ca4d353f3ab3ec"},
	{"issue1002.pdf", "f56a73d0ce26f32e5b944f079ea2a34abcb3032e0e5be661c3ceaf337c17abed"},
	{"issue10402.pdf", "f19aa17aae85e18e441363ce927d8d793d41eb59ea811d0332ebbb536f0c58f9"},
	{"cidfont_cmap_overflow.pdf", "ecb07ca4b3c6a9fd408db07c29c7e4426fb1bd6ee9e2bbdfa4997b65be602c13"},
	{"encrypted-attachment.pdf", "0f44da5152adf8cafcd7b0057d840310d78e17d033ee5414da0881b6dcd130ab"},
}

// The tests' own documents, written by the bench, and the password each opens with.
@(private = "file")
OWN_SAMPLE    :: "feuille-sample-form.pdf"
@(private = "file")
OWN_ENCRYPTED :: "feuille-encrypted-form.pdf"
@(private = "file")
OWN_PASSWORD  :: "secret"

// One file's results.
@(private = "file")
Bench_File :: struct {
	name:         string,
	pages:        int,
	pdfium_error: string,   // "": opened
	hayro_error:  string,   // "": opened (a page's failure is counted apart)
	hayro_failed: int,      // pages hayro could not render
	pdfium_ms:    f64,      // all its pages
	hayro_ms:     f64,
	worst:        f64,      // the share of differing pixels on the worst page, 0 to 1 (-1: nothing compared)
	worst_page:   int,
}

run_bench :: proc(args: []string) -> cli.Exit {
	when ODIN_OS != .Linux {
		fmt.eprintln("bench: Linux only (hayro runs under timeout)")
		return .Failed
	}
	if len(args) > 0 { fmt.eprintfln("bench: what is %s?", args[0]); return .Usage }
	corpus := BENCH_DIR + "/corpus"
	_ = os.make_directory_all(corpus)
	// the corpus, pinned
	for c in BENCH_CORPUS {
		url := fmt.tprintf("https://raw.githubusercontent.com/mozilla/pdf.js/%s/test/pdfs/%s", PDFJS_COMMIT, c[0])
		if why := toolbox.download_pinned(url, fmt.tprintf("%s/%s", corpus, c[0]), c[1], quiet = true); why != "" {
			fmt.eprintfln("bench: %s", why)
			return .Failed
		}
	}
	_ = os.write_entire_file(fmt.tprintf("%s/%s", corpus, OWN_SAMPLE), fixture.make_sample(context.temp_allocator))
	_ = os.write_entire_file(fmt.tprintf("%s/%s", corpus, OWN_ENCRYPTED), fixture.make_pdf({layer = true, password = OWN_PASSWORD}, context.temp_allocator))

	// hayro's side, and PDFium beside this tool (build/)
	if !toolbox.run({"cargo", "build", "--release", "--quiet", "--manifest-path", "tools/bench/hayro/Cargo.toml", "--target-dir", BENCH_DIR + "/target"}, {echo = true}) { return .Failed }
	if !pdfium_prepare({}) { return .Failed }
	if !pdf.init() {
		fmt.eprintln("bench: libpdfium does not load")
		return .Failed
	}

	names := make([dynamic]string, context.temp_allocator)
	for c in BENCH_CORPUS { append(&names, c[0]) }
	append(&names, OWN_SAMPLE, OWN_ENCRYPTED)
	results := make([dynamic]Bench_File, context.temp_allocator)
	for name in names {
		r := bench_file(corpus, name)
		append(&results, r)
		fmt.printfln("%-40s %s", name, summary_line(r))
	}
	report := bench_report(results[:])
	path := BENCH_DIR + "/report.md"
	if os.write_entire_file(path, transmute([]u8)report) != nil { fmt.eprintfln("bench: %s cannot be written", path); return .Failed }
	fmt.printfln("bench: %s", path)
	return .Done
}

@(private = "file")
summary_line :: proc(r: Bench_File) -> string {
	h := r.hayro_error != "" ? fmt.tprintf("hayro: %s", r.hayro_error) : fmt.tprintf("hayro %.0f ms, %d failed", r.hayro_ms, r.hayro_failed)
	p := r.pdfium_error != "" ? fmt.tprintf("pdfium: %s", r.pdfium_error) : fmt.tprintf("pdfium %.0f ms", r.pdfium_ms)
	d := r.worst >= 0 ? fmt.tprintf("worst page %d: %.1f %% apart", r.worst_page + 1, r.worst * 100) : "not compared"
	return fmt.tprintf("%d pages · %s · %s · %s", r.pages, p, h, d)
}

@(private = "file")
bench_file :: proc(corpus, name: string) -> (r: Bench_File) {
	r.name, r.worst = name, -1
	path := fmt.tprintf("%s/%s", corpus, name)
	out := fmt.tprintf("%s/pages/%s", BENCH_DIR, name)
	_ = os.remove_all(out)
	_ = os.make_directory_all(out)

	// hayro first: its pictures' sizes are the ones PDFium renders at
	password := name == OWN_ENCRYPTED ? OWN_PASSWORD : ""
	text, _ := toolbox.capture({"timeout", BENCH_TIMEOUT, BENCH_DIR + "/target/release/hayro-bench", path, out, fmt.tprintf("%v", BENCH_SCALE), password})
	hayro_pages := make(map[int]f64, context.temp_allocator)
	if strings.trim_space(text) == "" { r.hayro_error = "no answer (a crash or the timeout)" }
	for line in strings.split_lines(text, context.temp_allocator) {
		f := strings.fields(line, context.temp_allocator)
		if len(f) == 0 { continue }
		switch f[0] {
		case "open": r.hayro_error = strings.join(f[1:], " ", context.temp_allocator)
		case "fail": r.hayro_failed += 1
		case "page":
			if len(f) < 3 { continue }
			i, _ := strconv.parse_int(f[1])
			ms, _ := strconv.parse_f64(f[2])
			hayro_pages[i] = ms
			r.hayro_ms += ms
		}
	}

	bytes, rerr := os.read_entire_file_from_path(path, context.allocator)
	if rerr != nil { r.pdfium_error = "unreadable"; return }
	doc, err := pdf.open(bytes, password)
	if err != .None {
		delete(bytes)
		r.pdfium_error = fmt.tprintf("%v", err)
		return
	}
	defer pdf.close(&doc)
	r.pages = pdf.page_count(doc)
	for i in 0 ..< r.pages {
		size, _ := pdf.page_size(doc, i)
		w, h := int(size.x * BENCH_SCALE), int(size.y * BENCH_SCALE)
		hayro_pixels: []u8
		if _, ok := hayro_pages[i]; ok {
			if raw, e := os.read_entire_file_from_path(fmt.tprintf("%s/%d.rgba", out, i), context.temp_allocator); e == nil && len(raw) >= 8 {
				w = int(u32(raw[0]) | u32(raw[1]) << 8 | u32(raw[2]) << 16 | u32(raw[3]) << 24)
				h = int(u32(raw[4]) | u32(raw[5]) << 8 | u32(raw[6]) << 16 | u32(raw[7]) << 24)
				hayro_pixels = raw[8:]
			}
		}
		start := time.tick_now()
		masked := pdf.render(&doc, i, w, h, false)
		r.pdfium_ms += time.duration_milliseconds(time.tick_since(start))
		defer delete(masked)
		// (PDFium's picture beside hayro's, in the same form, to look at the two)
		if masked != nil { write_rgba(fmt.tprintf("%s/%d.pdfium.rgba", out, i), w, h, masked) }
		if masked == nil || len(hayro_pixels) != len(masked) { continue }
		if d := apart(masked, hayro_pixels); d > r.worst { r.worst, r.worst_page = d, i }
	}
	return
}

// A picture as hayro-bench writes them: its width and height (two little-endian u32), then its RGBA.
@(private = "file")
write_rgba :: proc(path: string, w, h: int, pixels: []u8) {
	head := [8]u8{u8(w), u8(w >> 8), u8(w >> 16), u8(w >> 24), u8(h), u8(h >> 8), u8(h >> 16), u8(h >> 24)}
	f, err := os.create(path)
	if err != nil { return }
	defer os.close(f)
	_, _ = os.write(f, head[:])
	_, _ = os.write(f, pixels)
}

// The share of pixels whose channels are more than BENCH_DIFF_MIN apart.
@(private = "file")
apart :: proc(a, b: []u8) -> f64 {
	if a == nil || len(a) != len(b) { return 1 }
	n := 0
	for i := 0; i + 3 < len(a); i += 4 {
		d := max(abs(int(a[i]) - int(b[i])), abs(int(a[i + 1]) - int(b[i + 1])), abs(int(a[i + 2]) - int(b[i + 2])))
		if d > BENCH_DIFF_MIN { n += 1 }
	}
	return f64(n) / f64(max(len(a) / 4, 1))
}

@(private = "file")
bench_report :: proc(results: []Bench_File) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintfln(&b, "# PDFium and hayro\n")
	fmt.sbprintfln(&b, "`feuilletool bench`, %v pixels per point. Corpus: pdf.js's test suite at %s, and feuille's own sample form and encrypted form. Both draw the page's own content only (feuille's masked opening). A pixel differs when a channel is more than %d apart: text edges and hairlines differ by their anti-aliasing, so a dense page of text equal to the eye is up to 8 per cent apart (TAMReview, 160F, checked by eye).\n", BENCH_SCALE, PDFJS_COMMIT[:12], BENCH_DIFF_MIN)
	opened_p, opened_h, failed_pages, close, compared: int
	tp, th: f64
	for r in results {
		if r.pdfium_error == "" { opened_p += 1 }
		if r.hayro_error == "" { opened_h += 1 }
		failed_pages += r.hayro_failed
		if r.worst >= 0 {
			compared += 1
			if r.worst < 0.01 { close += 1 }
		}
		if r.pdfium_error == "" && r.hayro_error == "" {
			tp += r.pdfium_ms
			th += r.hayro_ms
		}
	}
	fmt.sbprintfln(&b, "| | PDFium | hayro |\n|---|---|---|")
	fmt.sbprintfln(&b, "| files opened (of %d) | %d | %d |", len(results), opened_p, opened_h)
	fmt.sbprintfln(&b, "| pages that failed | 0 | %d |", failed_pages)
	fmt.sbprintfln(&b, "| time, files both opened | %.0f ms | %.0f ms |", tp, th)
	fmt.sbprintfln(&b, "| files whose worst page is under 1 %% apart | | %d of %d compared |\n", close, compared)
	sorted := slice.clone(results, context.temp_allocator)
	slice.sort_by(sorted, proc(a, b: Bench_File) -> bool { return a.worst > b.worst })
	fmt.sbprintfln(&b, "| File | Pages | PDFium | hayro | Worst page apart |\n|---|---|---|---|---|")
	for r in sorted {
		p := r.pdfium_error != "" ? r.pdfium_error : fmt.tprintf("%.0f ms", r.pdfium_ms)
		h := r.hayro_error != "" ? r.hayro_error : fmt.tprintf("%.0f ms%s", r.hayro_ms, r.hayro_failed > 0 ? fmt.tprintf(", %d failed", r.hayro_failed) : "")
		d := r.worst >= 0 ? fmt.tprintf("%.1f %% (page %d)", r.worst * 100, r.worst_page + 1) : "—"
		fmt.sbprintfln(&b, "| %s | %d | %s | %s | %s |", r.name, r.pages, p, h, d)
	}
	return strings.to_string(b)
}
