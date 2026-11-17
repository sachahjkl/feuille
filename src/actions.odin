package feuille

// Every act of the program, named once: its label, group, keys and icon (gui_toolkit's commands). The same table gives
// the keys, the tools' tips, the command palette (Ctrl+K) and the sheet of the keys (F1). The page edits act on the
// selected page (a click on a page or a thumbnail selects it).

import "core:fmt"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"
import update "gt:update"

Action :: enum u8 {
	Open,
	Save,
	Extract_Page,
	Undo,
	Redo,
	Rotate_Right,
	Rotate_Left,
	Remove_Page,
	Insert_Blank,
	Insert_File,
	Move_Up,
	Move_Down,
	Edit_Text,
	Layer,
	Thumbnails,
	Zoom_In,
	Zoom_Out,
	Fit,
	Previous_Page,
	Next_Page,
	First_Page,
	Last_Page,
	Settings,
	Check_Updates,
	Shortcuts,
	Restart,
	Quit,
}

ACTIONS := [Action]ui.Command{
	.Open          = {id = "open", label = i18n.later("Open a PDF…"), group = i18n.later("Document"), keys = {{.O, {.Ctrl}}}, icon = lucide.FOLDER_OPEN, tags = {"file", "load"}, scope = .Window},
	.Save          = {id = "save", label = i18n.later("Save a copy…"), group = i18n.later("Document"), keys = {{.S, {.Ctrl}}}, icon = lucide.SAVE, tags = {"write", "export", "save as"}},
	.Extract_Page  = {id = "extract_page", label = i18n.later("Save this page as a PDF…"), group = i18n.later("Document"), keys = {{.E, {.Ctrl}}}, icon = lucide.FILE_OUTPUT, tags = {"extract", "split", "export"}},
	.Undo          = {id = "undo", label = i18n.later("Undo"), group = i18n.later("Edit"), keys = {{.Z, {.Ctrl}}}, icon = lucide.UNDO_2, tags = {"back", "revert"}},
	.Redo          = {id = "redo", label = i18n.later("Redo"), group = i18n.later("Edit"), keys = {{.Z, {.Ctrl, .Shift}}, {.Y, {.Ctrl}}}, icon = lucide.REDO_2, tags = {"again"}},
	.Rotate_Right  = {id = "rotate_right", label = i18n.later("Turn the page right"), group = i18n.later("Page"), keys = {{.R, {.Ctrl}}}, icon = lucide.ROTATE_CW, tags = {"rotate", "clockwise", "orientation"}},
	.Rotate_Left   = {id = "rotate_left", label = i18n.later("Turn the page left"), group = i18n.later("Page"), keys = {{.R, {.Ctrl, .Shift}}}, icon = lucide.ROTATE_CCW, tags = {"rotate", "anticlockwise", "orientation"}},
	.Remove_Page   = {id = "remove_page", label = i18n.later("Remove the page"), group = i18n.later("Page"), keys = {{.Delete, {}}}, icon = lucide.TRASH_2, tags = {"delete", "erase"}},
	.Insert_Blank  = {id = "insert_blank", label = i18n.later("Add a blank page after"), group = i18n.later("Page"), keys = {{.N, {.Ctrl, .Shift}}}, icon = lucide.FILE_PLUS, tags = {"new", "empty", "insert"}},
	.Insert_File   = {id = "insert_file", label = i18n.later("Add the pages of a PDF after…"), group = i18n.later("Page"), keys = {{.I, {.Ctrl}}}, icon = lucide.FILE_INPUT, tags = {"import", "merge", "combine", "append"}},
	.Move_Up       = {id = "move_up", label = i18n.later("Move the page up"), group = i18n.later("Page"), keys = {{.Up, {.Alt}}}, icon = lucide.ARROW_UP_TO_LINE, tags = {"reorder", "earlier"}},
	.Move_Down     = {id = "move_down", label = i18n.later("Move the page down"), group = i18n.later("Page"), keys = {{.Down, {.Alt}}}, icon = lucide.ARROW_DOWN_TO_LINE, tags = {"reorder", "later"}},
	.Edit_Text     = {id = "edit_text", label = i18n.later("Edit a text block (click it)"), group = i18n.later("Edit"), keys = {{.F2, {}}}, icon = lucide.TYPE, tags = {"words", "change", "modify", "write"}, toggle = true},
	.Layer         = {id = "layer", label = i18n.later("Show the form layer"), group = i18n.later("View"), keys = {{.L, {.Ctrl}}}, icon = lucide.LAYERS_2, tags = {"signatures", "annotations", "fields", "form"}, toggle = true},
	.Thumbnails    = {id = "thumbnails", label = i18n.later("Show the thumbnails"), group = i18n.later("View"), keys = {{.B, {.Ctrl}}}, icon = lucide.PANEL_LEFT, tags = {"sidebar", "pages", "overview"}, toggle = true},
	.Zoom_In       = {id = "zoom_in", label = i18n.later("Zoom in"), group = i18n.later("View"), icon = lucide.ZOOM_IN, tags = {"bigger", "magnify"}},
	.Zoom_Out      = {id = "zoom_out", label = i18n.later("Zoom out"), group = i18n.later("View"), icon = lucide.ZOOM_OUT, tags = {"smaller"}},
	.Fit           = {id = "fit", label = i18n.later("Fit the width"), group = i18n.later("View"), icon = lucide.MOVE_HORIZONTAL, tags = {"zoom", "reset", "width"}},
	.Previous_Page = {id = "previous_page", label = i18n.later("Previous page"), group = i18n.later("View"), keys = {{.Page_Up, {}}}, icon = lucide.CHEVRON_UP, tags = {"back"}},
	.Next_Page     = {id = "next_page", label = i18n.later("Next page"), group = i18n.later("View"), keys = {{.Page_Down, {}}}, icon = lucide.CHEVRON_DOWN, tags = {"forward"}},
	.First_Page    = {id = "first_page", label = i18n.later("First page"), group = i18n.later("View"), keys = {{.Home, {.Ctrl}}}, icon = lucide.ARROW_UP, tags = {"top", "start"}},
	.Last_Page     = {id = "last_page", label = i18n.later("Last page"), group = i18n.later("View"), keys = {{.End, {.Ctrl}}}, icon = lucide.ARROW_DOWN, tags = {"bottom", "end"}},
	.Settings      = {id = "settings", label = i18n.later("Settings"), group = i18n.later("Feuille"), keys = {{.Comma, {.Ctrl}}}, icon = lucide.SETTINGS, tags = {"preferences", "options", "configure"}, scope = .Window},
	.Check_Updates = {id = "check_updates", label = i18n.later("Check for updates"), group = i18n.later("Feuille"), icon = lucide.REFRESH_CW, tags = {"upgrade", "version", "new"}},
	.Shortcuts     = {id = "shortcuts", label = i18n.later("Keyboard shortcuts"), group = i18n.later("Feuille"), keys = {{.F1, {}}}, icon = lucide.KEYBOARD, tags = {"help", "keys", "hotkeys"}, scope = .Window},
	.Restart       = {id = "restart", label = i18n.later("Restart Feuille"), group = i18n.later("Feuille"), icon = lucide.ROTATE_CCW, tags = {"reload", "relaunch"}},
	.Quit          = {id = "quit", label = i18n.later("Quit Feuille"), group = i18n.later("Feuille"), keys = {{.Q, {.Ctrl}}}, icon = lucide.POWER, tags = {"exit", "close", "stop"}, scope = .Window},
}

// Whether the act can be done now.
action_enabled :: proc(app: ^App, a: Action) -> bool {
	s := app.snapshot
	doc := s != nil && !app.settings_open && app.pending != .Locked
	index := selected_index(app)
	switch a {
	case .Undo:          return doc && s.can_undo
	case .Redo:          return doc && s.can_redo
	case .Remove_Page:   return doc && index >= 0 && len(s.pages) > 1
	case .Move_Up:       return doc && index > 0
	case .Move_Down:     return doc && index >= 0 && index < len(s.pages) - 1
	case .Save, .Extract_Page, .Rotate_Right, .Rotate_Left, .Insert_Blank, .Insert_File, .Edit_Text,
	     .Layer, .Thumbnails, .Zoom_In, .Zoom_Out, .Fit, .Previous_Page, .Next_Page, .First_Page, .Last_Page:
		return doc
	case .Open, .Settings, .Check_Updates, .Shortcuts, .Restart, .Quit:
		return true
	}
	return false
}

// Whether a switch of the table is on.
action_on :: proc(app: ^App, a: Action) -> bool {
	#partial switch a {
	case .Layer:      return app.layer
	case .Thumbnails: return app.thumbs_shown
	case .Edit_Text:  return app.text_mode
	}
	return false
}

action_run :: proc(app: ^App, a: Action) {
	if !action_enabled(app, a) { return }
	w := &app.worker
	id := app.selected
	switch a {
	case .Open:
		leave_document(app, .Open_Dialog)
	case .Save:
		ui.file_dialog(&app.main.state, .Save, {owner = app.main.win, title = i18n.tr("Save a copy"), filters = PDF_FILTERS[:], start_dir = filepath.dir(app.snapshot.path), suggested_name = suggested_name(app, i18n.tr("edited")), default_ext = "pdf", overwrite_prompt = true}, save_chosen, app)
	case .Extract_Page:
		ui.file_dialog(&app.main.state, .Save, {owner = app.main.win, title = i18n.tr("Save this page as a PDF"), filters = PDF_FILTERS[:], start_dir = filepath.dir(app.snapshot.path), suggested_name = suggested_name(app, fmt.tprintf(i18n.tr("page %d"), selected_index(app) + 1)), default_ext = "pdf", overwrite_prompt = true}, extract_chosen, app)
	case .Undo:          worker_edit(w, edit_ask_make(w, .Undo))
	case .Redo:          worker_edit(w, edit_ask_make(w, .Redo))
	case .Rotate_Right:  worker_edit(w, edit_ask_make(w, .Rotate, id = id, turns = 1))
	case .Rotate_Left:   worker_edit(w, edit_ask_make(w, .Rotate, id = id, turns = -1))
	case .Remove_Page:   worker_edit(w, edit_ask_make(w, .Remove, id = id))
	case .Insert_Blank:  worker_edit(w, edit_ask_make(w, .Blank, id = id))
	case .Insert_File:
		ui.file_dialog(&app.main.state, .Open, {owner = app.main.win, title = i18n.tr("Add the pages of a PDF"), filters = PDF_FILTERS[:], all_files = true}, insert_chosen, app)
	case .Move_Up:       worker_edit(w, edit_ask_make(w, .Move, id = id, to = selected_index(app) - 1))
	case .Move_Down:     worker_edit(w, edit_ask_make(w, .Move, id = id, to = selected_index(app) + 1))
	case .Edit_Text:
		app.text_mode = !app.text_mode
		if app.text_mode { say(app, i18n.tr("Click a text block to change its words; Escape leaves")) }
	case .Layer:         app.layer = !app.layer
	case .Thumbnails:    app.thumbs_shown = !app.thumbs_shown
	case .Zoom_In:       ui.zoom_zone_by(&app.zone, ui.feel(&app.main.state).zoom_step)
	case .Zoom_Out:      ui.zoom_zone_by(&app.zone, 1 / ui.feel(&app.main.state).zoom_step)
	case .Fit:           ui.zoom_zone_reset(&app.zone)
	case .Previous_Page: go_to_page(app, max(app.current - 1, 0))
	case .Next_Page:     go_to_page(app, min(app.current + 1, len(app.snapshot.pages) - 1))
	case .First_Page:    go_to_page(app, 0)
	case .Last_Page:     go_to_page(app, len(app.snapshot.pages) - 1)
	case .Settings:      settings_toggle(app)
	case .Check_Updates: if app.updates.updater != nil { update.check_now(app.updates.updater) }
	// (the sheet adds the toolkit's palette command itself)
	case .Shortcuts:     ui.shortcuts_sheet_open(&app.sheet, slice.enumerated_array(&ACTIONS), i18n.tr("Feuille's keys"))
	case .Restart:       leave_document(app, .Restart)
	case .Quit:          leave_document(app, .Quit)
	}
}

// The page brought to the top of the view, and selected.
go_to_page :: proc(app: ^App, index: int) {
	if app.snapshot == nil || index < 0 || index >= len(app.snapshot.pages) { return }
	app.go_to = index
	app.selected = app.snapshot.pages[index].id
}

// "<name> (<what>).pdf" beside the document.
@(private = "file")
suggested_name :: proc(app: ^App, what: string) -> string {
	return fmt.tprintf("%s (%s).pdf", filepath.stem(filepath.base(app.snapshot.path)), what)
}

// The keys of the window's actions (scope .Window): in every page, before anything else reads a key. The palette's
// first: its keys are the toolkit's, read by its own reader.
window_keys :: proc(app: ^App) {
	if palette_keys(app) { return }
	for a in Action {
		if ACTIONS[a].scope != .Window { continue }
		if ui.command_pressed(ACTIONS[a], !action_enabled(app, a)) { action_run(app, a); return }
	}
}

// The keys of the document's actions, when nothing else has the keyboard.
actions_keys :: proc(app: ^App) {
	for a in Action {
		if ACTIONS[a].scope == .Window { continue }
		if ui.command_pressed(ACTIONS[a], !action_enabled(app, a)) { action_run(app, a); return }
	}
}

// (package arrays: the dialog reads them on another thread, after the build that asked)
@(rodata) PDF_PATTERNS := [?]string{"*.pdf"}
PDF_FILTERS := [?]platform.File_Filter{{name = "PDF", patterns = PDF_PATTERNS[:]}}

@(private = "file")
open_chosen :: proc(r: platform.Dialog_Result, user: rawptr) {
	if r.status != .Chosen || len(r.paths) == 0 { return }
	app_open_file((^App)(user), r.paths[0], "")
}

@(private = "file")
insert_chosen :: proc(r: platform.Dialog_Result, user: rawptr) {
	app := (^App)(user)
	if r.status != .Chosen || len(r.paths) == 0 || app.snapshot == nil { return }
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Import, id = app.selected, path = r.paths[0]))
}

@(private = "file")
save_chosen :: proc(r: platform.Dialog_Result, user: rawptr) {
	app := (^App)(user)
	if r.status != .Chosen || len(r.paths) == 0 || app.snapshot == nil { return }
	path := r.paths[0]
	// (the original itself: asked once more, in the window's words; any other file is a new copy)
	if path == app.snapshot.path {
		delete(app.overwrite)
		app.overwrite = strings.clone(path)
		ui.confirm_open("overwrite", {title = i18n.tr("Replace the original?"), note = i18n.tr("The file opened is written over with the edited document. A copy beside it keeps the original."), act = i18n.tr("Replace")})
		return
	}
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Save, path = path))
}

@(private = "file")
extract_chosen :: proc(r: platform.Dialog_Result, user: rawptr) {
	app := (^App)(user)
	if r.status != .Chosen || len(r.paths) == 0 || app.snapshot == nil { return }
	ids := []u64{app.selected}
	worker_edit(&app.worker, edit_ask_make(&app.worker, .Extract, path = r.paths[0], ids = ids))
}

// What waits for the document to be left: an edited document asks first (Save, Discard, Cancel).
Leave_Next :: enum u8 { None, Open_Dialog, Open_File, Quit, Restart }

leave_document :: proc(app: ^App, next: Leave_Next) {
	if app.snapshot != nil && app.snapshot.edited {
		app.leave_next = next
		ui.confirm_open("discard", {title = i18n.tr("Leave the edits unsaved?"), note = i18n.tr("The changes made to this document since it was opened or saved are lost. Save a copy first to keep them."), act = i18n.tr("Leave them")})
		return
	}
	leave_now(app, next)
}

leave_now :: proc(app: ^App, next: Leave_Next) {
	switch next {
	case .None:
	case .Open_Dialog:
		app.settings_open = false
		ui.file_dialog(&app.main.state, .Open, {owner = app.main.win, title = i18n.tr("Open a PDF"), filters = PDF_FILTERS[:], all_files = true}, open_chosen, app)
	case .Open_File:
		app_open_file(app, app.leave_path, "")
	case .Quit:    app.quit = true
	case .Restart: app_restart(app)
	}
}

// The answers of the confirmations, at each build.
confirms_follow :: proc(app: ^App) {
	switch ui.confirm_answer("discard") {
	case .Confirmed:
		next := app.leave_next
		app.leave_next = .None
		leave_now(app, next)
	case .Cancelled: app.leave_next = .None
	case .None:
	}
	switch ui.confirm_answer("overwrite") {
	case .Confirmed:
		worker_edit(&app.worker, edit_ask_make(&app.worker, .Save, path = app.overwrite))
	case .Cancelled, .None:
	}
}

// The palette is the toolkit's: its commands source lists the actions, prefs_page's settings source the settings (`:`).
Palette_State :: struct {
	disabled: [Action]bool,   // the actions that cannot act, as the commands source last took them
	version:  u64,
	made_for: Palette_Key,
	made:     bool,
	settings: prefs_page.Palette_Settings,
}

// What action_enabled reads: when one moves, `disabled` is read again.
Palette_Key :: struct {
	revision: u64,
	selected: u64,
	settings: bool,
	pending:  Pending,
}

palette_init :: proc(app: ^App) {
	if !app.headless { ui.palette_memory_open(&app.palette, &app.main.state, palette_choices_path()) }
	open :: proc(user: rawptr) { (^App)(user).settings_open = true }
	options :: proc(user: rawptr) -> prefs_page.Page_Options { return settings_options((^App)(user)) }
	prefs_page.palette_settings_add(&app.palette, &app.palette_state.settings, &app.prefs, &app.settings_page, options, open, app)
}

@(private = "file")
palette_give :: proc(app: ^App) {
	ps := &app.palette_state
	key := Palette_Key{app.snapshot != nil ? app.snapshot.revision : 0, app.selected, app.settings_open, app.pending}
	if !ps.made || key != ps.made_for {
		for a in Action { ps.disabled[a] = !action_enabled(app, a) }
		ps.made_for, ps.made = key, true
		ps.version += 1
	}
	ui.palette_commands(&app.palette, slice.enumerated_array(&ACTIONS), slice.enumerated_array(&ps.disabled), {version = ps.version})
}

// Ctrl+K and Ctrl+Shift+P: the palette opens or closes. True when they were pressed.
palette_keys :: proc(app: ^App) -> bool {
	if !ui.palette_keys(&app.palette) { return false }
	palette_give(app)
	return true
}

// The palette's choice, the confirmations' answers, and what can act kept while the palette is open: at each build.
actions_build :: proc(app: ^App) {
	if c, ok := ui.palette_chosen(&app.palette); ok {
		if i, is := ui.palette_chosen_command(&app.palette, c); is && i >= 0 && i < len(Action) { action_run(app, Action(i)) }
	}
	confirms_follow(app)
	if ui.palette_is_open(&app.palette) { palette_give(app) }
}
