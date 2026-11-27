package feuille

// The signature's dialog, its pad and its placing (src/md/features/signature.md). The interface draws the font list
// and the pad itself, so typing and drawing never wait; the preview under them is the preview thread's picture
// (signature_thread.odin), the signature as it goes on the page.

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import fsx "gt:fsx"
import "core:path/filepath"
import "core:strings"
import "gt:draw"
import "gt:platform"
import "gt:tasks"
import "gt:font"
import host "gt:host"
import i18n "gt:i18n"
import ink "gt:ink"
import lucide "gt:lucide"
import pdf "gt:pdf"
import "gt:render"
import store "gt:store"
import "gt:ui"

SIGN_VIEW :: "signature"
// The dialog's answer that places the signature.
SIGN_PLACE :: 1
// The pad keeps a sample when the pointer went this far, in the pad's units.
SIGN_STEP :: 1.5

// The signature's state in the window: what the dialog edits, the engine's fonts, the newest preview.
Sign_State :: struct {
	thread:    Sign_Thread,
	store:     store.Store,
	lib:       [dynamic]Signature,         // the signatures kept (owned); `sig` is written back to lib[chosen] (sign_sync)
	chosen:    int,
	sig:       Signature,                  // what the dialog edits and a click places: the chosen one (owned)
	faces:     [Script]pdf.Face,           // the engine's ids of the fonts (faces_ok: given)
	faces_ok:  bool,
	ui_fonts:  [Script]font.Font_Id,       // the interface's copies, for the list (0: not read yet)
	name:      ui.Line_Edit,
	place:     ui.Line_Edit,
	version:   u64,                        // moves with each change of `sig`
	asked:     u64,                        // the version last asked of the preview thread
	preview:   ^Sign_Preview,              // the newest answer (owned; nil: none yet)
	tex:       render.Texture,
	tex_size:  [2]int,                     // {}: no texture
	zoom:      ui.Preview,                 // the preview's zoom and pan (ui.preview)
	detail:    f32,                        // the preview's pixels a point at the zoom shown (sign_detail)
	detail_asked: f32,
	paper_h:   f32,                        // the preview's height as the last build laid it out
	tab:       int,                        // the dialog's tab (Sign_Mode)
	focus:     bool,                       // the next build gives the name's field the keyboard
	pad:       [dynamic]draw.Path,         // each stroke's outline in the pad's units: the pad draws a stroke the
	                                       // engine's picture does not hold yet (the one under way) with it
	pad_tex:   render.Texture,             // the engine's picture of the finished strokes' ink (pad_tex_px: {}: none)
	pad_tex_px: [2]int,
	pad_shown: int,                        // the strokes it holds, the first ones
	pad_tex_epoch: u64,                    // the epoch it was made for
	pad_epoch: u64,                        // moves with every change of the pad but a stroke added: the picture is stale
	pad_px:    [2]int,                     // the pad's size in pixels, as the last build laid it out
	pad_px_asked: [2]int,
	drawing:   bool,                       // a stroke under way
	stroke_ms: f64,                        // its start, ui clock
	hover:     Sign_Hover,
}

// Where the pointer is over a page while the tool is on: the ghost of the signature follows it.
Sign_Hover :: struct {
	id:    u64,
	at:    [2]f32,   // shares of the page shown
	frame: u64,      // the frame that saw it
}

sign_init :: proc(app: ^App) {
	s := &app.sign
	store.open(&s.store, app.headless ? "" : signatures_path())
	s.lib, s.chosen = signatures_load(&s.store)
	s.pad = make([dynamic]draw.Path)
	sign_take(app, s.chosen)
	sign_thread_start(&s.thread, {state = &app.main.state, user = app, faces = on_sign_faces, preview = on_sign_preview, linear = render.blend_space(&app.shared.r) == .Linear})
	ui.view_register(&app.views, SIGN_VIEW, signature_view, {title = i18n.later("Signature"), icon = lucide.SIGNATURE, icon_font = ui.lucide_icons(), width_em = 40, min_width_em = 34, resizable = true})
}

// Before the renderer goes: the thread ends, the texture goes, the store writes what is left.
sign_close :: proc(app: ^App) {
	s := &app.sign
	sign_thread_stop(&s.thread)
	if s.tex_size != {} { render.destroy_texture(&app.shared.r, s.tex) }
	s.tex_size = {}
	if s.pad_tex_px != {} { render.destroy_texture(&app.shared.r, s.pad_tex) }
	s.pad_tex_px = {}
	if s.preview != nil { sign_preview_free(s.preview) }
	s.preview = nil
	sign_keep(app)
	store.close(&s.store)
	signature_free(&s.sig)
	for &l in s.lib { signature_free(&l) }
	delete(s.lib)
	ui.line_edit_destroy(&s.name)
	ui.line_edit_destroy(&s.place)
	for &p in s.pad { draw.path_destroy(&p) }
	delete(s.pad)
}

@(private = "file")
on_sign_faces :: proc(data: rawptr, _: u64) {
	f := (^Sign_Faces)(data)
	defer free(f)
	app := (^App)(f.user)
	app.sign.faces, app.sign.faces_ok = f.faces, f.ok
	host.host_settle(&app.main)
}

@(private = "file")
on_sign_preview :: proc(data: rawptr, _: u64) {
	p := (^Sign_Preview)(data)
	app := (^App)(p.user)
	s := &app.sign
	// (an answer older than the one shown: a newer ask overtook it)
	if s.preview != nil && p.serial < s.preview.serial {
		sign_preview_free(p)
		return
	}
	if s.preview != nil { sign_preview_free(s.preview) }
	s.preview = p
	r := &app.shared.r
	if s.tex_size != p.px && s.tex_size != {} {
		render.destroy_texture(r, s.tex)
		s.tex_size = {}
	}
	if p.rgba != nil {
		if s.tex_size == {} { s.tex = render.create_texture_rgba(r, p.px.x, p.px.y) }
		s.tex_size = p.px
		render.update_texture_rgba(r, s.tex, 0, 0, p.px.x, p.px.y, p.rgba)
	}
	if p.pad_rgba != nil {
		if s.pad_tex_px != p.pad_px && s.pad_tex_px != {} {
			render.destroy_texture(r, s.pad_tex)
			s.pad_tex_px = {}
		}
		if s.pad_tex_px == {} { s.pad_tex = render.create_texture_rgba(r, p.pad_px.x, p.pad_px.y) }
		s.pad_tex_px = p.pad_px
		render.update_texture_rgba(r, s.pad_tex, 0, 0, p.pad_px.x, p.pad_px.y, p.pad_rgba)
		s.pad_shown, s.pad_tex_epoch = p.pad_strokes, p.epoch
	}
	host.host_settle(&app.main)
}

// The marks a click places now (nil: none: the fonts are not given yet, nothing to place, or its preview is older
// than the signature).
sign_ready_marks :: proc(app: ^App) -> ^Sign_Marks {
	s := &app.sign
	p := s.preview
	if p == nil || p.serial != s.version || p.marks.size.x <= 0 { return nil }
	return &p.marks
}

// The signature changed: a new preview is asked at the end of the build.
sign_changed :: proc(app: ^App) {
	app.sign.version += 1
}

// Each build: the newest signature to the preview thread, and the dialog's answer.
sign_follow :: proc(app: ^App) {
	s := &app.sign
	// (the pad's picture asked again when the pad changed size: the dialog resized)
	// (and the preview again when its zoom needs finer pixels)
	if s.detail <= 0 { s.detail = ui.scale() * 2 }
	if s.faces_ok && (s.asked != s.version || s.pad_px != s.pad_px_asked || s.detail != s.detail_asked) {
		s.asked, s.pad_px_asked, s.detail_asked = s.version, s.pad_px, s.detail
		sign_thread_ask(&s.thread, s.version, s.sig, s.detail, ui.view_is_open(&app.views, SIGN_VIEW) ? s.pad_px : {}, s.pad_epoch)
	}
	if code, ok := ui.view_ended(&app.views, SIGN_VIEW); ok {
		sign_keep(app)
		if code == SIGN_PLACE {
			say(app, i18n.tr("Click on a page to sign there; Escape leaves"))
		} else if app.tool == .Signature {
			tool_toggle(app, .Signature)
		}
	}
}

// The dialog, with the signature kept; its fonts read into the interface at its first opening.
sign_open :: proc(app: ^App) {
	s := &app.sign
	for f, k in SCRIPTS {
		if s.ui_fonts[k] != 0 { continue }
		// (compiled in: read in place, nothing from the disk)
		if id, ok := font.load_embedded(&app.shared.fonts, f.data); ok { s.ui_fonts[k] = id }
	}
	s.focus = s.sig.mode == .Typed
	ui.view_open(&app.views, SIGN_VIEW, app)
}

// The signature placed on page `p`, centred on `at` (shares of the page shown).
sign_place :: proc(app: ^App, p: Snapshot_Page, at: [2]f32) {
	m := sign_ready_marks(app)
	if m == nil || p.size.x <= 0 || p.size.y <= 0 { return }
	w := &app.worker
	a := edit_ask_make(w, .Sign, id = p.id)
	a.at = at - m.size / 2 / p.size
	a.marks = sign_marks_clone(m^, w.allocator)
	worker_edit(w, a)
}

// The ink's colour: the next signatures', and the chosen signature mark's.
sign_ink_set :: proc(app: ^App, c: [3]u8) {
	s := &app.sign
	if s.sig.ink == c { return }
	s.sig.ink = c
	s.pad_epoch += 1
	sign_changed(app)
	sign_keep(app)
	ch := app.chosen
	if ch.kind == .None || app.snapshot == nil { return }
	w := &app.worker
	if ch.group != 0 {
		worker_edit(w, group_ask_make(w, ch.id, ch.group, color = c))
		return
	}
	for q in app.snapshot.pages {
		if q.id != ch.id { continue }
		if ch.kind == .Stamp && ch.index < len(q.stamps) {
			st := q.stamps[ch.index].stamp
			st.color = c
			worker_edit(w, stamp_ask_make(w, ch.id, ch.index, st, st.text))
		}
		if ch.kind == .Shape && ch.index < len(q.shapes) && q.shapes[ch.index].shape.kind == .Outline {
			style := q.shapes[ch.index].shape
			style.fill = {c[0], c[1], c[2], 255}
			worker_edit(w, shape_ask_make(w, ch.id, ch.index, style))
		}
	}
}

////////////////////////////////
// The library

// The signature edited written back to its place in the library.
@(private = "file")
sign_sync :: proc(s: ^Sign_State) {
	context.allocator = runtime.heap_allocator()
	if s.chosen < 0 || s.chosen >= len(s.lib) { return }
	signature_free(&s.lib[s.chosen])
	s.lib[s.chosen] = signature_clone(s.sig)
}

// The library to its store: the signature edited first.
sign_keep :: proc(app: ^App) {
	s := &app.sign
	sign_sync(s)
	signatures_keep(&s.store, s.lib[:], s.chosen)
}

// Signature `i` of the library becomes the one edited (what was edited is not written back: the caller syncs first).
@(private = "file")
sign_take :: proc(app: ^App, i: int) {
	context.allocator = runtime.heap_allocator()
	s := &app.sign
	s.chosen = clamp(i, 0, len(s.lib) - 1)
	signature_free(&s.sig)
	s.sig = signature_clone(s.lib[s.chosen])
	if s.sig.date.year <= 0 {
		s.sig.date = signature_today()
	}
	s.tab = int(s.sig.mode)
	ui.line_edit_set(&s.name, s.sig.name)
	ui.line_edit_set(&s.place, s.sig.place)
	s.drawing = false
	sign_pad_redo(s)
	sign_changed(app)
}

// Another signature of the library chosen.
sign_choose :: proc(app: ^App, i: int) {
	if i == app.sign.chosen { return }
	sign_sync(&app.sign)
	sign_take(app, i)
	sign_keep(app)
}

// A new signature, the defaults, chosen: typed when the one before was, drawn when it was drawn.
sign_new :: proc(app: ^App) {
	context.allocator = runtime.heap_allocator()
	s := &app.sign
	sign_sync(s)
	n := SIGNATURE_DEFAULT
	n.mode = s.sig.mode
	// (the language of the one before: a person signs a run of documents in one language)
	n.lang = s.sig.lang
	n.strokes = make([dynamic]Stroke)
	append(&s.lib, n)
	sign_take(app, len(s.lib) - 1)
	s.focus = n.mode == .Typed
	sign_keep(app)
}

// The chosen signature removed; never the last one.
sign_remove :: proc(app: ^App) {
	s := &app.sign
	if len(s.lib) <= 1 { return }
	signature_free(&s.lib[s.chosen])
	ordered_remove(&s.lib, s.chosen)
	sign_take(app, min(s.chosen, len(s.lib) - 1))
	sign_keep(app)
}

// What a card of the library shows: a typed one its name in its hand, a drawn one its number among the drawn.
@(private = "file")
sign_label :: proc(s: ^Sign_State, i: int) -> string {
	g := s.lib[i]
	if i == s.chosen { g = s.sig }
	if name := strings.trim_space(g.name); g.mode == .Typed && name != "" { return name }
	if g.mode == .Typed { return i18n.tr("Typed signature") }
	n := 0
	for k in 0 ..= i {
		if (k == s.chosen ? s.sig : s.lib[k]).mode == .Drawn { n += 1 }
	}
	return fmt.tprintf(i18n.tr("Drawn %d"), n)
}

////////////////////////////////
// Export and import: a task of the program's pool reads and writes the file

@(private = "file")
Sign_File_Job :: struct {
	app:     ^App,
	path:    string,               // owned
	list:    [dynamic]Signature,   // export: what is written; import: what is kept, then what the file adds (owned)
	import_: bool,
	ok:      bool,
	added:   int,                  // import: how many of `list` are new (its last ones)
}

@(private = "file")
sign_file_job_free :: proc(j: ^Sign_File_Job) {
	context.allocator = runtime.heap_allocator()
	delete(j.path)
	for &l in j.list { signature_free(&l) }
	delete(j.list)
	free(j)
}

// Export (`import_` false) or import the file at `path` on the pool; what comes of it is said in the status bar.
sign_file_start :: proc(app: ^App, path: string, import_: bool) {
	context.allocator = runtime.heap_allocator()
	sign_sync(&app.sign)
	j := new(Sign_File_Job)
	j.app, j.path, j.import_ = app, strings.clone(path), import_
	j.list = make([dynamic]Signature)
	for l in app.sign.lib { append(&j.list, signature_clone(l)) }
	if !tasks.add(&app.pool, sign_file_work, j) { sign_file_job_free(j) }
}

@(private = "file")
sign_file_work :: proc(data: rawptr) {
	j := (^Sign_File_Job)(data)
	context.allocator = runtime.heap_allocator()
	if j.import_ {
		bytes, err := os.read_entire_file_from_path(j.path, context.temp_allocator)
		if err == nil {
			read, ok := signatures_parse(string(bytes))
			j.ok = ok
			keys := make(map[string]bool, len(j.list) + len(read), context.temp_allocator)
			for l in j.list { keys[signature_key(l)] = true }
			for &r in read {
				k := signature_key(r)
				if k in keys {
					signature_free(&r)
					continue
				}
				keys[k] = true
				append(&j.list, r)
				j.added += 1
			}
			delete(read)
		}
	} else {
		text := signatures_text(j.list[:], context.temp_allocator)
		j.ok = fsx.write_atomic(j.path, transmute([]u8)text, fsx.DOCUMENT)
	}
	if !ui.post(&j.app.main.state, sign_file_done, j) { sign_file_job_free(j) }
}

@(private = "file")
sign_file_done :: proc(data: rawptr, _: u64) {
	j := (^Sign_File_Job)(data)
	defer sign_file_job_free(j)
	app := j.app
	base := filepath.base(j.path)
	switch {
	case !j.ok && j.import_: say(app, i18n.tr("%s holds no signatures"), base)
	case !j.ok:              say(app, i18n.tr("%s cannot be written"), base)
	case !j.import_:         say(app, i18n.tr("The signatures are saved in %s"), base)
	case j.added == 0:       say(app, i18n.tr("The signatures of %s are already kept"), base)
	case:
		s := &app.sign
		sign_sync(s)
		first := len(s.lib)
		for &l in j.list[len(j.list) - j.added:] {
			append(&s.lib, l)
			l = {}   // (the library owns it now)
		}
		sign_take(app, first)
		sign_keep(app)
		say(app, i18n.tr("%d signatures added from %s"), j.added, base)
	}
	host.host_settle(&app.main)
}

@(private = "file")
SIGN_FILTERS := [?]platform.File_Filter{{name = "Signatures", patterns = {"*." + SIGNATURES_EXT}}}

@(private = "file")
sign_export_chosen :: proc(r: platform.Dialog_Result, user: rawptr) {
	if r.status == .Chosen && len(r.paths) > 0 { sign_file_start((^App)(user), r.paths[0], false) }
}

@(private = "file")
sign_import_chosen :: proc(r: platform.Dialog_Result, user: rawptr) {
	if r.status == .Chosen && len(r.paths) > 0 { sign_file_start((^App)(user), r.paths[0], true) }
}

sign_export :: proc(app: ^App) {
	ui.file_dialog(&app.main.state, .Save, {owner = app.main.win, title = i18n.tr("Export the signatures"), filters = SIGN_FILTERS[:], suggested_name = "signatures." + SIGNATURES_EXT, default_ext = SIGNATURES_EXT, overwrite_prompt = true, remember_id = "signatures"}, sign_export_chosen, app)
}

sign_import :: proc(app: ^App) {
	ui.file_dialog(&app.main.state, .Open, {owner = app.main.win, title = i18n.tr("Import signatures"), filters = SIGN_FILTERS[:], all_files = true, remember_id = "signatures"}, sign_import_chosen, app)
}

////////////////////////////////
// The dialog

// The library's row: a card a signature, the chosen one held; add, remove, import, export.
@(private = "file")
library_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	ui.next({width = ui.fill(), height = ui.children_sum()})
	if ui.row(.Center) {
		gap := math.round(em * 0.35)
		ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X, gap = {gap, gap}})
		if ui.parent(ui.build_box({.Wrap}, "###sign_library")) {
			for _, i in s.lib {
				g := i == s.chosen ? s.sig : s.lib[i]
				label := sign_label(s, i)
				if g.mode == .Typed && strings.trim_space(g.name) != "" {
					ui.next({height = ui.px(em * 2.3), font = s.ui_fonts[g.script], font_size = em * 1.25 * SCRIPTS[g.script].scale})
					if ui.button(fmt.tprintf("sign_card%d", i), label, o = {face = i == s.chosen ? .Toggled : .Raised, tip = label}).clicked { sign_choose(app, i) }
				} else {
					ui.next({height = ui.px(em * 2.3)})
					glyph := g.mode == .Drawn ? lucide.PEN_TOOL : lucide.KEYBOARD
					if ui.button(fmt.tprintf("sign_card%d", i), label, glyph, {face = i == s.chosen ? .Toggled : .Raised, icon_font = ui.lucide_icons()}).clicked { sign_choose(app, i) }
				}
			}
			ui.next({width = ui.px(em * 2.3), height = ui.px(em * 2.3)})
			if ui.button("sign_new", icon = lucide.PLUS, o = {tip = i18n.tr("A new signature"), icon_font = ui.lucide_icons()}).clicked { sign_new(app) }
		}
		ui.space(ui.CONTROL_GAP)
		ui.next({width = ui.px(em * 2.3), height = ui.px(em * 2.3)})
		if ui.button("sign_remove", icon = lucide.TRASH_2, o = {tip = i18n.tr("Remove this signature"), icon_font = ui.lucide_icons(), disabled = len(s.lib) <= 1}).clicked { sign_remove(app) }
		ui.next({width = ui.px(em * 2.3), height = ui.px(em * 2.3)})
		if ui.button("sign_import", icon = lucide.FILE_INPUT, o = {tip = i18n.tr("Import signatures…"), icon_font = ui.lucide_icons()}).clicked { sign_import(app) }
		ui.next({width = ui.px(em * 2.3), height = ui.px(em * 2.3)})
		if ui.button("sign_export", icon = lucide.FILE_OUTPUT, o = {tip = i18n.tr("Export the signatures…"), icon_font = ui.lucide_icons()}).clicked { sign_export(app) }
	}
}

@(private = "file")
signature_view :: proc(v: ^ui.View, app: ^App) {
	context.allocator = runtime.heap_allocator()   // (the signature's strings are the App's)
	s := &app.sign
	sig := &s.sig
	em := ui.font_size()
	// (stretched: the preview takes what a taller dialog gives)
	if ui.dialog_body("body", stretch = true) {
		library_part(app, em)
		ui.space(ui.SPACE_3)
		// (the toolkit's tabs, the line under them across the dialog, and under it the chosen tab's page: the tab and what
		// it shows are one shape, as a folder's tab and its sheet; tabs.md)
		ui.next({width = ui.fill(), height = ui.px(math.round(em * SIGN_TABS_EM)), axis = .X})
		tab_row := ui.build_box({}, "###sign_tab_row")
		tab_row.custom = ui.tab_line_draw
		if ui.parent(tab_row) {
			if ui.tabs("sign_tabs", {i18n.tr("Type it"), i18n.tr("Draw it")}, {lucide.TYPE, lucide.PENCIL}, &s.tab) {
				sig.mode = Sign_Mode(s.tab)
				s.focus = sig.mode == .Typed
				sign_changed(app)
			}
		}
		page: ui.Color
		if ui.tags("tab_on") { page = ui.color("background") }
		page.a = 1
		pad := math.round(em * SIGN_TAB_PAGE_PAD_EM)
		ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X, bg = page, radius = 0})
		if ui.parent(ui.build_box({.Draw_Background, .Draw_Border}, "###sign_tab_page")) {
			ui.spacer(ui.px(pad))
			ui.next({width = ui.fill(), height = ui.children_sum(), axis = .Y})
			if ui.parent(ui.build_box({}, "###sign_tab_col")) {
				ui.spacer(ui.px(pad))
				switch sig.mode {
				case .Typed: typed_part(app, em)
				case .Drawn: drawn_part(app, em)
				}
				ui.spacer(ui.px(pad))
			}
			ui.spacer(ui.px(pad))
		}
		ui.space(ui.SPACE_3)
		common_part(app, em)
		ui.space(ui.SPACE_3)
		preview_part(app, em)
	}
	if ui.dialog_buttons("buttons") {
		if ui.button("sign_cancel", i18n.tr("Cancel")).clicked { ui.view_end(v, ui.VIEW_CANCELLED) }
		ready := signature_ready(sig^) && s.faces_ok
		if ui.button("sign_place", i18n.tr("Place on the page"), lucide.SIGNATURE, {intent = .Primary, disabled = !ready, icon_font = ui.lucide_icons()}).clicked {
			ui.view_end(v, SIGN_PLACE)
		}
	}
}

@(private = "file")
typed_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	ui.next({width = ui.fill()})
	res := ui.line_edit("###sign_name", &s.name, {placeholder = i18n.tr("Your name, as you sign it")})
	if s.focus {
		ui.set_focus(res.box.key)
		s.focus = false
	}
	if res.changed {
		delete(s.sig.name)
		s.sig.name = strings.clone(ui.line_edit_string(&s.name))
		sign_changed(app)
	}
	ui.space(ui.SPACE_2)
	// (each font shows the name in it: the person chooses the hand, not a font's name)
	shown := strings.trim_space(s.sig.name)
	gap := math.round(em * 0.4)
	ui.next({width = ui.fill(), height = ui.children_sum(), axis = .X, gap = {gap, gap}})
	if ui.parent(ui.build_box({.Wrap}, "###sign_fonts")) {
		for f, k in SCRIPTS {
			word := shown != "" ? shown : f.name
			ui.next({width = ui.px(em * 11.6), height = ui.px(em * 3.4), font = s.ui_fonts[k], font_size = em * 1.6 * f.scale, text_pad = em * 0.6})
			if ui.button(fmt.tprintf("sign_script%d", int(k)), word, o = {face = s.sig.script == k ? .Toggled : .Raised, tip = f.name}).clicked && s.sig.script != k {
				s.sig.script = k
				sign_changed(app)
			}
		}
	}
	ui.space(ui.SPACE_2)
	if ui.form_row(i18n.tr("Slant")) {
		if ui.slider("###sign_tilt", &s.sig.tilt, -10, 15, 1, "%.0f°", 4) { sign_changed(app) }
	}
	if ui.form_row(i18n.tr("Pen weight")) {
		if ui.slider("###sign_weight", &s.sig.weight, 0, 60, 5, "%.0f", 20) { sign_changed(app) }
	}
	ui.next({width = ui.fill()})
	if ui.toggle("###sign_flourish", i18n.tr("A flourish under the name"), &s.sig.flourish) { sign_changed(app) }
}

@(private = "file")
drawn_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	pad_build(app, em)
	ui.space(ui.SPACE_2)
	ui.next({width = ui.fill(), height = ui.children_sum()})
	if ui.row(.Center) {
		pen := int(s.sig.pen)
		if ui.segmented("###sign_pen", {i18n.tr("Ballpoint"), i18n.tr("Fountain pen"), i18n.tr("Felt pen"), i18n.tr("Brush")}, &pen) {
			s.sig.pen = Pen_Kind(pen)
			sign_pad_redo(s)
			sign_changed(app)
		}
		ui.spacer(ui.fill())
		if ui.button("sign_undo_stroke", icon = lucide.UNDO_2, o = {tip = i18n.tr("Remove the last stroke"), icon_font = ui.lucide_icons(), disabled = len(s.sig.strokes) == 0}).clicked {
			delete(pop(&s.sig.strokes))
			last := pop(&s.pad)
			draw.path_destroy(&last)
			s.pad_epoch += 1
			sign_changed(app)
		}
		ui.space(ui.ICON_GAP)
		if ui.button("sign_clear", i18n.tr("Clear"), lucide.ERASER, {icon_font = ui.lucide_icons(), disabled = len(s.sig.strokes) == 0}).clicked {
			for t in s.sig.strokes { delete(t) }
			clear(&s.sig.strokes)
			sign_pad_redo(s)
			sign_changed(app)
		}
	}
	if ui.form_row(i18n.tr("Pen thickness")) {
		if ui.slider("###sign_thickness", &s.sig.thickness, 0.5, 2.5, 0.1, "%.1f", 1.2) {
			sign_pad_redo(s)
			sign_changed(app)
		}
	}
}

@(private = "file")
common_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	ui.next({width = ui.fill(), height = ui.children_sum()})
	if ui.row(.Center) {
		for c, i in SIGN_INKS {
			if swatch(fmt.tprintf("###sign_ink%d", i), {c[0], c[1], c[2], 255}, s.sig.ink == c, em, i18n.tr("Ink")) {
				s.sig.ink = c
				s.pad_epoch += 1
				sign_changed(app)
			}
		}
		ui.space(ui.SPACE_3)
		if ui.tags("weak") {
			ui.next({width = ui.text_size(), height = ui.px(ui.control_height())})
			ui.label(fmt.tprintf("%s###sign_size_lbl", i18n.tr("Size")))
		}
		ui.space(ui.CONTROL_GAP)
		ui.next({width = ui.fill(), height = ui.px(ui.control_height())})
		ui.a11y({name = i18n.tr("Size")})
		if ui.slider("###sign_scale", &s.sig.scale, 0.5, 2, 0.05, "%.2f×", 1) { sign_changed(app) }
		ui.space(ui.SPACE_3)
		// (the words of the document's language, whatever the program's: each language named in itself)
		names := make([]string, len(Sign_Lang), context.temp_allocator)
		for w, k in SIGN_WORDS { names[int(k)] = w.name }
		lang := int(s.sig.lang)
		ui.next({height = ui.px(ui.control_height())})
		ui.a11y({name = i18n.tr("Language of the signature's words")})
		if ui.dropdown("###sign_lang", names, &lang) {
			s.sig.lang = Sign_Lang(lang)
			sign_changed(app)
		}
	}
	ui.space(ui.SPACE_1)
	ui.next({width = ui.fill()})
	if ui.toggle("###sign_mention", fmt.tprintf(i18n.tr("“%s” above it"), SIGN_WORDS[s.sig.lang].mention), &s.sig.mention) { sign_changed(app) }
	ui.next({width = ui.fill()})
	if ui.toggle("###sign_dated", i18n.tr("The place and the date under it"), &s.sig.dated) { sign_changed(app) }
	if s.sig.dated {
		ui.space(ui.SPACE_1)
		ui.next({width = ui.fill(), height = ui.children_sum()})
		if ui.row(.Center) {
			ui.next({width = ui.fill(), height = ui.px(ui.control_height())})
			if ui.line_edit("###sign_where", &s.place, {placeholder = i18n.tr("Place")}).changed {
				delete(s.sig.place)
				s.sig.place = strings.clone(ui.line_edit_string(&s.place))
				sign_changed(app)
			}
			ui.space(ui.CONTROL_GAP)
			if date_picker(s) { sign_changed(app) }
		}
	}
}

// A field of three parts (day, month, year), typed or stepped one by one, with their drums in a popover: month
// names when the signature's language writes them in words, numbers otherwise.
@(private = "file")
date_picker :: proc(s: ^Sign_State) -> bool {
	d := s.sig.date
	if d.year <= 0 { d = signature_today() }
	d.month = clamp(d.month, 1, 12)
	d.year = clamp(d.year, 1970, 2100)
	d.day = clamp(d.day, 1, days_in_month(d.month, d.year))
	words := SIGN_WORDS[s.sig.lang].months[0] != ""
	sep := SIGN_WORDS[s.sig.lang].date_sep
	parts := [3]ui.Field_Part{
		{lo = 1, hi = days_in_month(d.month, d.year), format = words ? "%d" : "%02d", wrap = true},
		words ? ui.Field_Part{labels = SIGN_WORDS[s.sig.lang].months[:], wrap = true} : ui.Field_Part{lo = 1, hi = 12, format = "%02d", before = sep, wrap = true},
		{lo = 1970, hi = 2100, before = words ? "" : sep},
	}
	values := [3]int{d.day, words ? d.month - 1 : d.month, d.year}
	ui.next({height = ui.px(ui.control_height())})
	ui.a11y({name = i18n.tr("Date")})
	if !ui.parts_field("###sign_when", parts[:], values[:]) { return false }
	month := words ? values[1] + 1 : values[1]
	year := values[2]
	s.sig.date = {year, month, min(values[0], days_in_month(month, year))}
	return true
}

// The preview's least height, in ems: what it takes in a dialog not made taller.
SIGN_PREVIEW_LEAST_EM :: 7
// The row of the tabs Type it and Draw it, in ems.
SIGN_TABS_EM :: 2.4
// The margin inside the chosen tab's page, in ems.
SIGN_TAB_PAGE_PAD_EM :: 0.8
// ... and the height, in ems, from which it shows the zoom's bar.
SIGN_PREVIEW_BAR_EM :: 12
// The paper around the signature, in device pixels at the zoom 100 %.
SIGN_PAPER_MARGIN :: 12
// The finest picture the zoom asks: this many times the interface's pixels (the engine renders it on each change).
SIGN_DETAIL_MOST :: 8

// What the preview draws: the paper over all of its box, and the signature in the rectangle the zoom gives it.
@(private = "file")
Sign_Paper :: struct {
	tex:    render.Texture,
	has:    bool,
	edge:   draw.Color,
	scale:  f32,
	margin: f32,   // of the content's width
}

@(private = "file")
sign_paper_draw :: proc(dc: ^draw.Context, dst: ui.Rect, user: rawptr) {
	d := (^Sign_Paper)(user)
	r := draw.current_clip(dc)   // (the preview's box: it clips what it draws)
	draw.rect(dc, r, draw.WHITE, radius = 4 * d.scale)
	draw.rect(dc, r, d.edge, radius = 4 * d.scale, border = d.scale)
	if !d.has { return }
	inset := (dst.max.x - dst.min.x) * d.margin
	draw.image(dc, d.tex, {dst.min + inset, dst.max - inset})
}

// The signature on paper, fitted to the room the dialog gives; the wheel, a double click, the keys and the bar in its
// corner zoom it and a drag moves it (ui.preview). A zoom past the picture's pixels asks a finer one.
@(private = "file")
preview_part :: proc(app: ^App, em: f32) {
	s := &app.sign
	scale := ui.scale()
	d := ui.frame_new(Sign_Paper)
	d.tex, d.has = s.tex, s.tex_size != {} && s.preview != nil && s.preview.rgba != nil
	d.edge, d.scale = ui.color("border"), scale
	// (the content in device pixels at the zoom 100 %: the signature's points at the interface's scale, and its paper)
	content := [2]f32{1, 1}
	if d.has {
		ink := [2]f32{f32(s.tex_size.x), f32(s.tex_size.y)} * scale / s.preview.px_per_pt
		margin := SIGN_PAPER_MARGIN * scale
		content = ink + 2 * margin
		d.margin = margin / content.x
	}
	ui.next({width = ui.fill(), height = ui.fill_least(em * SIGN_PREVIEW_LEAST_EM)})
	// (the zoom's bar over a small preview hides the signature: it shows once the dialog is made taller)
	bar := s.paper_h >= em * SIGN_PREVIEW_BAR_EM
	res := ui.preview("###sign_preview", &s.zoom, content, sign_paper_draw, d, {buttons = bar, grow = true})
	s.paper_h = res.box.rect.max.y - res.box.rect.min.y
	if ui.a11y_wanted() { ui.a11y_set(res.box, {role = .Image, name = i18n.tr("The signature as it goes on the page")}) }
	// (no picture yet: its size is not known, nor the zoom it fits at)
	if d.has { s.detail = sign_detail(scale, res.percent / 100) }
}

// The preview's pixels a point for a zoom of `shown` device pixels a content's pixel: twice what is shown (a picture as
// sharp as the interface's text), in steps of two so a zoom that moves renders again only at each step.
sign_detail :: proc(scale, shown: f32) -> f32 {
	step: f32 = 1
	for step < shown && step < SIGN_DETAIL_MOST / 2 { step *= 2 }
	return scale * 2 * step
}

////////////////////////////////
// The pad

// What the pad draws: paper, a line to sign on, the engine's picture of the finished strokes, and the strokes it does
// not hold yet as their outlines (the one under way: drawn at once, its ink comes with the next picture).
@(private = "file")
Pad_Draw :: struct {
	tex:     render.Texture,
	has_tex: bool,
	live:    []draw.Path,
	ink:     draw.Color,
	line:    draw.Color,
	edge:    draw.Color,
	scale:   f32,
}

@(private = "file")
pad_draw :: proc(b: ^ui.Box, user: rawptr, dc: ^draw.Context) {
	d := (^Pad_Draw)(user)
	r := b.rect
	draw.rect(dc, r, draw.WHITE, radius = 4 * d.scale)
	draw.rect(dc, r, d.edge, radius = 4 * d.scale, border = d.scale)
	size := r.max - r.min
	k := size / SIGN_PAD
	y := r.min.y + size.y * 0.74
	x0, x1 := r.min.x + size.x * 0.06, r.max.x - size.x * 0.06
	draw.line(dc, {x0, y}, {x1, y}, d.scale, d.line)
	// (the cross where one signs, as on a form)
	c, h := [2]f32{x0 + 6 * d.scale, y - 9 * d.scale}, 4 * d.scale
	draw.line(dc, c - h, c + h, 1.5 * d.scale, d.line)
	draw.line(dc, {c.x - h, c.y + h}, {c.x + h, c.y - h}, 1.5 * d.scale, d.line)
	if d.has_tex { draw.image(dc, d.tex, r) }
	draw.push_transform(dc, draw.affine_mul(draw.affine_translate(r.min), draw.affine_scale(k)))
	for &p in d.live { draw.path_fill(dc, &p, d.ink) }
	draw.pop_transform(dc)
}

@(private = "file")
pad_build :: proc(app: ^App, em: f32) {
	s := &app.sign
	d := ui.frame_new(Pad_Draw)
	// (the picture holds the first pad_shown strokes of this epoch; the strokes after them are drawn live)
	first := 0
	if s.pad_tex_px != {} && s.pad_tex_epoch == s.pad_epoch && s.pad_shown <= len(s.pad) {
		d.tex, d.has_tex, first = s.pad_tex, true, s.pad_shown
	}
	d.live = s.pad[first:]
	c := s.sig.ink
	opacity := sign_pen(s.sig).ink.opacity
	d.ink = draw.srgb(f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255, opacity > 0 ? opacity : 1)
	d.line, d.edge, d.scale = draw.srgb(0.75, 0.77, 0.8), ui.color("border"), ui.scale()
	ui.next({width = ui.fill(), height = ui.px(em * 12)})
	b := ui.custom("###sign_pad", pad_draw, d, {.Clickable})
	b.cursor = .Crosshair
	if ui.a11y_wanted() { ui.a11y_set(b, {role = .Image, name = i18n.tr("Draw your signature here")}) }
	sig := ui.signal(b)
	size := b.rect.max - b.rect.min
	if size.x <= 0 || size.y <= 0 { return }
	s.pad_px = {int(math.round(size.x * ui.scale())), int(math.round(size.y * ui.scale()))}
	at := [2]f32{clamp(sig.mouse.x / size.x, 0, 1), clamp(sig.mouse.y / size.y, 0, 1)} * SIGN_PAD
	now := ui.now_ms()
	// (a stylus's pressure and lean where the system gives them; 0, a mouse: the ink follows the speed, upright)
	pressure := ui.pointer_pressure()
	device := ui.pointer_device()
	tilt := device.kind == .Pen ? device.tilt : {}
	if sig.pressed && !s.drawing {
		s.drawing, s.stroke_ms = true, now
		st := make(Stroke)
		append(&st, ink.Sample{at = at, pressure = pressure, tilt = tilt})
		append(&s.sig.strokes, st)
		append(&s.pad, draw.path_make())
		pad_stroke(s, len(s.sig.strokes) - 1)
	}
	if !s.drawing || len(s.sig.strokes) == 0 { return }
	st := &s.sig.strokes[len(s.sig.strokes) - 1]
	if sig.dragging {
		last := st[len(st) - 1].at
		if d := at - last; d.x * d.x + d.y * d.y >= SIGN_STEP * SIGN_STEP {
			append(st, ink.Sample{at = at, time = now - s.stroke_ms, pressure = pressure, tilt = tilt})
			pad_stroke(s, len(s.sig.strokes) - 1)
		}
		host.host_settle(&app.main)
	}
	if sig.released || (!sig.dragging && !sig.pressed) {
		s.drawing = false
		sign_changed(app)
	}
}

// The outline of stroke `i` of the pad, made again from its samples: one contour, the pen's width.
@(private = "file")
pad_stroke :: proc(s: ^Sign_State, i: int) {
	o := ink.outline(s.sig.strokes[i][:], sign_pen(s.sig), context.temp_allocator)
	poly := ink.polygon(o, context.temp_allocator)
	p := &s.pad[i]
	draw.path_clear(p)
	if len(poly) < 3 { return }
	draw.path_move_to(p, poly[0])
	for q in poly[1:] { draw.path_line_to(p, q) }
	draw.path_close(p)
}

// Every stroke's outline made again, the picture stale until the next one: a new pen, a stroke removed, cleared.
sign_pad_redo :: proc(s: ^Sign_State) {
	context.allocator = runtime.heap_allocator()
	for &p in s.pad { draw.path_destroy(&p) }
	clear(&s.pad)
	for _ in s.sig.strokes { append(&s.pad, draw.path_make()) }
	for _, i in s.sig.strokes { pad_stroke(s, i) }
	s.pad_epoch += 1
}
