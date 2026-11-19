package feuille

// Every act of the program, named once: its label, group, keys and icon (gui_toolkit's commands). The same table gives
// the keys, the tools' tips, the command palette (Ctrl+K) and the sheet of the keys (F1). The page edits act on the
// selected page (a click on a page or a thumbnail selects it).

import "base:runtime"
import "core:fmt"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import i18n "gt:i18n"
import lucide "gt:lucide"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

Action :: enum u8 {
	Open,
	Save,
	Print,
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
	Draw_Rect,
	Draw_Ellipse,
	Draw_Line,
	Draw_Arrow,
	Draw_Pen,
	Highlight,
	Remove_Mark,
	Layer,
	Thumbnails,
	Zoom_In,
	Zoom_Out,
	Fit,
	Previous_Page,
	Next_Page,
	First_Page,
	Last_Page,
	Open_With,
	Reveal,
	Copy_Path,
	Go_To_Page,
	Recent,
	Settings,
	Shortcuts,
	// the program's own (program_actions.odin): the suite's commands, by its ids and keys
	New_Window,
	Minimize,
	Maximize,
	Full_Screen,
	Check_Updates,
	Update_Install,
	Update_Restart,
	About,
	Website,
	Report,
	Changelog,
	Settings_Folder,
	Version_Copy,
	Theme_Next,
	Theme_Previous,
	Density,
	Animations,
	Text_Bigger,
	Text_Smaller,
	Text_Reset,
	Restart,
	Quit,
}

ACTIONS := [Action]ui.Command{
	.Open          = {id = "open", label = i18n.later("Open a PDF…"), group = i18n.later("Document"), keys = {{.O, {.Ctrl}}}, icon = lucide.FOLDER_OPEN, tags = {"file", "load"}, scope = .Window},
	.Save          = {id = "save", label = i18n.later("Save a copy…"), group = i18n.later("Document"), keys = {{.S, {.Ctrl}}}, icon = lucide.SAVE, tags = {"write", "export", "save as"}},
	.Print         = {id = "print", label = i18n.later("Print…"), group = i18n.later("Document"), keys = {{.P, {.Ctrl}}}, icon = lucide.PRINTER, tags = {"printer", "paper"}},
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
	.Edit_Text     = {id = "add_text", label = i18n.later("Put text on a page (click where)"), group = i18n.later("Edit"), keys = {{.T, {}}, {.F2, {}}}, icon = lucide.TYPE, tags = {"words", "write", "stamp", "sign", "type", "annotate", "text box"}, toggle = true},
	.Draw_Rect     = {id = "draw_rect", label = i18n.later("Draw a rectangle"), group = i18n.later("Edit"), keys = {{.R, {}}}, icon = lucide.SQUARE, tags = {"box", "frame", "shape", "annotate"}, toggle = true},
	.Draw_Ellipse  = {id = "draw_ellipse", label = i18n.later("Draw an ellipse (circle something)"), group = i18n.later("Edit"), keys = {{.E, {}}}, icon = lucide.CIRCLE, tags = {"circle", "ring", "round", "shape", "annotate"}, toggle = true},
	.Draw_Line     = {id = "draw_line", label = i18n.later("Draw a line"), group = i18n.later("Edit"), keys = {{.L, {}}}, icon = lucide.SLASH, tags = {"underline", "strike", "shape", "annotate"}, toggle = true},
	.Draw_Arrow    = {id = "draw_arrow", label = i18n.later("Draw an arrow"), group = i18n.later("Edit"), keys = {{.A, {}}}, icon = lucide.ARROW_UP_RIGHT, tags = {"point", "shape", "annotate"}, toggle = true},
	.Draw_Pen      = {id = "draw_pen", label = i18n.later("Draw freely (pen)"), group = i18n.later("Edit"), keys = {{.P, {}}}, icon = lucide.PENCIL, tags = {"ink", "freehand", "sign", "scribble", "annotate"}, toggle = true},
	.Highlight     = {id = "highlight", label = i18n.later("Highlight"), group = i18n.later("Edit"), keys = {{.H, {}}}, icon = lucide.HIGHLIGHTER, tags = {"marker", "mark", "annotate"}, toggle = true},
	.Remove_Mark   = {id = "remove_mark", label = i18n.later("Remove the chosen mark"), group = i18n.later("Edit"), keys = {{.Backspace, {}}}, icon = lucide.TRASH_2, tags = {"delete", "erase", "shape", "text"}},
	.Layer         = {id = "layer", label = i18n.later("Show the form layer"), group = i18n.later("View"), keys = {{.L, {.Ctrl}}}, icon = lucide.LAYERS_2, tags = {"signatures", "annotations", "fields", "form"}, toggle = true},
	.Thumbnails    = {id = "thumbnails", label = i18n.later("Show the thumbnails"), group = i18n.later("View"), keys = {{.B, {.Ctrl}}}, icon = lucide.PANEL_LEFT, tags = {"sidebar", "pages", "overview"}, toggle = true},
	.Zoom_In       = {id = "zoom_in", label = i18n.later("Zoom in"), group = i18n.later("View"), icon = lucide.ZOOM_IN, tags = {"bigger", "magnify"}},
	.Zoom_Out      = {id = "zoom_out", label = i18n.later("Zoom out"), group = i18n.later("View"), icon = lucide.ZOOM_OUT, tags = {"smaller"}},
	.Fit           = {id = "fit", label = i18n.later("Fit the width"), group = i18n.later("View"), icon = lucide.MOVE_HORIZONTAL, tags = {"zoom", "reset", "width"}},
	.Previous_Page = {id = "previous_page", label = i18n.later("Previous page"), group = i18n.later("View"), keys = {{.Page_Up, {}}}, icon = lucide.CHEVRON_UP, tags = {"back"}},
	.Next_Page     = {id = "next_page", label = i18n.later("Next page"), group = i18n.later("View"), keys = {{.Page_Down, {}}}, icon = lucide.CHEVRON_DOWN, tags = {"forward"}},
	.First_Page    = {id = "first_page", label = i18n.later("First page"), group = i18n.later("View"), keys = {{.Home, {.Ctrl}}}, icon = lucide.ARROW_UP, tags = {"top", "start"}},
	.Last_Page     = {id = "last_page", label = i18n.later("Last page"), group = i18n.later("View"), keys = {{.End, {.Ctrl}}}, icon = lucide.ARROW_DOWN, tags = {"bottom", "end"}},
	.Open_With     = {id = "open_with", label = i18n.later("Open with another application…"), group = i18n.later("Document"), icon = lucide.APP_WINDOW, tags = {"system's application", "external", "default app"}},
	.Reveal        = {id = "reveal", label = i18n.later("Show in folder"), group = i18n.later("Document"), icon = lucide.FOLDER_SEARCH, tags = {"file manager", "explorer", "where"}},
	.Copy_Path     = {id = "copy_path", label = i18n.later("Copy the path"), group = i18n.later("Document"), keys = {{.C, {.Ctrl, .Shift}}}, icon = lucide.LINK, tags = {"clipboard", "file name", "location"}},
	.Go_To_Page    = {id = "go_to_page", label = i18n.later("Go to a page…"), group = i18n.later("View"), keys = {{.G, {.Ctrl}}}, icon = lucide.HASH, tags = {"page number", "jump"}},
	.Recent        = {id = "recent", label = i18n.later("Open a recent PDF…"), group = i18n.later("Document"), keys = {{.O, {.Ctrl, .Shift}}}, icon = lucide.HISTORY, tags = {"history", "last", "reopen"}, scope = .Window},
	.Settings      = {id = "settings", label = i18n.later("Settings"), group = i18n.later("Feuille"), keys = {{.Comma, {.Ctrl}}}, icon = lucide.SETTINGS, tags = {"preferences", "options", "configure"}, scope = .Window},
	.Shortcuts     = {id = "shortcuts", label = i18n.later("Keyboard shortcuts"), group = i18n.later("Feuille"), keys = {{.F1, {}}}, icon = lucide.KEYBOARD, tags = {"help", "keys", "hotkeys"}, scope = .Window},
	.New_Window    = {id = "app_new_window", label = i18n.later("New window"), group = i18n.later("Window"), keys = {{.N, {.Ctrl}}}, icon = lucide.APP_WINDOW, tags = {"another window", "open"}, scope = .Window},
	.Minimize      = {id = "app_minimize", label = i18n.later("Minimize window"), group = i18n.later("Window"), keys = {{.F9, {.Alt}}}, icon = lucide.ARROW_DOWN, tags = {"hide", "iconify", "taskbar"}, scope = .Window},
	.Maximize      = {id = "app_maximize", label = i18n.later("Maximize window"), group = i18n.later("Window"), keys = {{.F10, {.Alt}}}, icon = lucide.MONITOR, tags = {"restore", "whole screen", "zoom window"}, scope = .Window},
	.Full_Screen   = {id = "app_full_screen", label = i18n.later("Full screen"), group = i18n.later("Window"), keys = {{.F11, {}}}, icon = lucide.FILM, tags = {"fullscreen", "kiosk", "whole screen"}, scope = .Window},
	.Check_Updates = {id = "app_update_check", label = i18n.later("Check for updates"), group = i18n.later("Feuille"), keys = {{.U, {.Ctrl, .Alt}}}, icon = lucide.DOWNLOAD, tags = {"upgrade", "new version", "release"}, scope = .Window},
	.Update_Install = {id = "app_update_install", label = i18n.later("Install the update"), group = i18n.later("Feuille"), keys = {{.U, {.Ctrl, .Shift, .Alt}}}, icon = lucide.HARD_DRIVE_DOWNLOAD, tags = {"upgrade", "download", "new version"}, scope = .Window},
	.Update_Restart = {id = "app_update_restart", label = i18n.later("Restart to update"), group = i18n.later("Feuille"), keys = {{.Q, {.Ctrl, .Shift, .Alt}}}, icon = lucide.FILE_DOWN, tags = {"relaunch", "upgrade", "new version"}, scope = .Window},
	.About         = {id = "app_about", label = i18n.later("About Feuille"), group = i18n.later("Feuille"), keys = {{.F1, {.Shift}}}, icon = lucide.LIGHTBULB, tags = {"version", "credits", "info"}, scope = .Window},
	.Website       = {id = "app_website", label = i18n.later("Open the website"), group = i18n.later("Feuille"), keys = {{.F1, {.Ctrl}}}, icon = lucide.GLOBE, tags = {"site", "home page", "web"}, scope = .Window},
	.Report        = {id = "app_report", label = i18n.later("Report a problem"), group = i18n.later("Feuille"), keys = {{.F1, {.Ctrl, .Shift}}}, icon = lucide.BUG, tags = {"bug", "issue", "feedback", "help"}, scope = .Window},
	.Changelog     = {id = "app_changelog", label = i18n.later("Release notes"), group = i18n.later("Feuille"), keys = {{.F2, {.Shift}}}, icon = lucide.SCROLL_TEXT, tags = {"changelog", "what is new", "changes", "releases"}, scope = .Window},
	.Settings_Folder = {id = "app_settings_folder", label = i18n.later("Open settings folder"), group = i18n.later("Feuille"), keys = {{.Comma, {.Ctrl, .Shift}}}, icon = lucide.WRENCH, tags = {"configuration", "config", "preferences file"}, scope = .Window},
	.Version_Copy  = {id = "app_version_copy", label = i18n.later("Copy the version"), group = i18n.later("Feuille"), keys = {{.V, {.Ctrl, .Shift, .Alt}}}, icon = lucide.CODE, tags = {"about", "number", "clipboard"}, scope = .Window},
	.Theme_Next    = {id = "app_theme_next", label = i18n.later("Next theme"), group = i18n.later("Appearance"), keys = {{.Period, {.Ctrl, .Shift, .Alt}}}, icon = lucide.PALETTE, tags = {"color", "colour", "dark", "light", "look"}, scope = .Window},
	.Theme_Previous = {id = "app_theme_previous", label = i18n.later("Previous theme"), group = i18n.later("Appearance"), keys = {{.Comma, {.Ctrl, .Shift, .Alt}}}, icon = lucide.PALETTE, tags = {"color", "colour", "dark", "light", "look"}, scope = .Window},
	.Density       = {id = "app_density", label = i18n.later("Compact rows"), group = i18n.later("Appearance"), keys = {{.D, {.Ctrl, .Shift, .Alt}}}, icon = lucide.MENU, tags = {"density", "comfortable", "spacing"}, scope = .Window},
	.Animations    = {id = "app_animations", label = i18n.later("Animations"), group = i18n.later("Appearance"), keys = {{.A, {.Ctrl, .Shift, .Alt}}}, icon = lucide.PLAY, tags = {"motion", "transitions", "on or off"}, scope = .Window},
	.Text_Bigger   = {id = "app_text_bigger", label = i18n.later("Larger text"), group = i18n.later("Appearance"), keys = {{.Equal, {.Ctrl, .Alt}}}, icon = lucide.TYPE, tags = {"font size", "bigger", "interface", "scale"}, scope = .Window},
	.Text_Smaller  = {id = "app_text_smaller", label = i18n.later("Smaller text"), group = i18n.later("Appearance"), keys = {{.Minus, {.Ctrl, .Alt}}}, icon = lucide.TYPE, tags = {"font size", "interface", "scale"}, scope = .Window},
	// (not Ctrl+0, the suite's key: here Ctrl+0 is the pages' zoom back to the width, the zoom zone's own key)
	.Text_Reset    = {id = "app_text_reset", label = i18n.later("Default text size"), group = i18n.later("Appearance"), keys = {{.N0, {.Ctrl, .Alt}}}, icon = lucide.TYPE, tags = {"font size", "reset", "interface", "scale"}, scope = .Window},
	.Restart       = {id = "app_restart", label = i18n.later("Restart Feuille"), group = i18n.later("Feuille"), keys = {{.Q, {.Ctrl, .Shift}}}, icon = lucide.ZAP, tags = {"relaunch", "reload", "reboot", "start again"}, scope = .Window},
	.Quit          = {id = "app_quit", label = i18n.later("Quit Feuille"), group = i18n.later("Feuille"), keys = {{.Q, {.Ctrl}}}, icon = lucide.POWER, tags = {"exit", "close", "leave"}, scope = .Window},
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
	case .Remove_Mark:   return doc && app.chosen.kind != .None
	case .Save, .Print, .Extract_Page, .Rotate_Right, .Rotate_Left, .Insert_Blank, .Insert_File, .Edit_Text,
	     .Draw_Rect, .Draw_Ellipse, .Draw_Line, .Draw_Arrow, .Draw_Pen, .Highlight, .Layer, .Thumbnails, .Zoom_In, .Zoom_Out, .Fit, .Previous_Page, .Next_Page, .First_Page, .Last_Page, .Go_To_Page:
		return doc
	// (the file's own acts: the document shown, whatever the page shows over it)
	case .Open_With, .Reveal, .Copy_Path:
		return s != nil
	case .Recent:         return len(app.memory.recent) > 0
	case .Check_Updates:  return has_updater(app)
	case .Update_Install: return update_available(app)
	case .Update_Restart: return update_installed(app)
	case .Open, .Settings, .Shortcuts, .Restart, .Quit, .New_Window, .Minimize, .Maximize, .Full_Screen, .About,
	     .Website, .Report, .Changelog, .Settings_Folder, .Version_Copy, .Theme_Next, .Theme_Previous, .Density,
	     .Animations, .Text_Bigger, .Text_Smaller, .Text_Reset:
		return true
	}
	return false
}

// Whether a switch of the table is on.
action_on :: proc(app: ^App, a: Action) -> bool {
	#partial switch a {
	case .Layer:      return app.layer
	case .Thumbnails: return app.thumbs_shown
	case .Edit_Text:    return app.tool == .Text
	case .Draw_Rect:    return app.tool == .Rect
	case .Draw_Ellipse: return app.tool == .Ellipse
	case .Draw_Line:    return app.tool == .Line
	case .Draw_Arrow:   return app.tool == .Arrow
	case .Draw_Pen:     return app.tool == .Pen
	case .Highlight:    return app.tool == .Highlight
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
	case .Print:
		// (the dialog and the pages on the worker's printing thread: the window never waits)
		a := edit_ask_make(w, .Print, path = filepath.base(app.snapshot.path))
		a.layer = app.layer   // (the pages as shown: with the layer when it is drawn)
		worker_edit(w, a)
	case .Extract_Page:
		ui.file_dialog(&app.main.state, .Save, {owner = app.main.win, title = i18n.tr("Save this page as a PDF"), filters = PDF_FILTERS[:], start_dir = filepath.dir(app.snapshot.path), suggested_name = suggested_name(app, fmt.tprintf(i18n.tr("page %d"), selected_index(app) + 1)), default_ext = "pdf", overwrite_prompt = true}, extract_chosen, app)
	case .Undo:          worker_edit(w, edit_ask_make(w, .Undo))
	case .Redo:          worker_edit(w, edit_ask_make(w, .Redo))
	case .Rotate_Right:  worker_edit(w, edit_ask_make(w, .Rotate, id = id, turns = 1))
	case .Rotate_Left:   worker_edit(w, edit_ask_make(w, .Rotate, id = id, turns = -1))
	case .Remove_Page:
		// (Delete with a mark chosen takes the mark, never its page)
		if !mark_remove(app) { worker_edit(w, edit_ask_make(w, .Remove, id = id)) }
	case .Insert_Blank:  worker_edit(w, edit_ask_make(w, .Blank, id = id))
	case .Insert_File:
		ui.file_dialog(&app.main.state, .Open, {owner = app.main.win, title = i18n.tr("Add the pages of a PDF"), filters = PDF_FILTERS[:], all_files = true, remember_id = "open"}, insert_chosen, app)
	case .Move_Up:       worker_edit(w, edit_ask_make(w, .Move, id = id, to = selected_index(app) - 1))
	case .Move_Down:     worker_edit(w, edit_ask_make(w, .Move, id = id, to = selected_index(app) + 1))
	case .Edit_Text:
		tool_toggle(app, .Text)
	case .Draw_Rect:     tool_toggle(app, .Rect)
	case .Draw_Ellipse:  tool_toggle(app, .Ellipse)
	case .Draw_Line:     tool_toggle(app, .Line)
	case .Draw_Arrow:    tool_toggle(app, .Arrow)
	case .Draw_Pen:      tool_toggle(app, .Pen)
	case .Highlight:     tool_toggle(app, .Highlight)
	case .Remove_Mark:   _ = mark_remove(app)
	case .Layer:         app.layer = !app.layer
	case .Thumbnails:    app.thumbs_shown = !app.thumbs_shown
	case .Zoom_In:       ui.zoom_zone_by(&app.zone, ui.feel(&app.main.state).zoom_step)
	case .Zoom_Out:      ui.zoom_zone_by(&app.zone, 1 / ui.feel(&app.main.state).zoom_step)
	case .Fit:           ui.zoom_zone_reset(&app.zone)
	case .Previous_Page: go_to_page(app, max(app.current - 1, 0))
	case .Next_Page:     go_to_page(app, min(app.current + 1, len(app.snapshot.pages) - 1))
	case .First_Page:    go_to_page(app, 0)
	case .Last_Page:     go_to_page(app, len(app.snapshot.pages) - 1)
	case .Go_To_Page:    palette_open_on(app, .Go_To)
	case .Recent:        palette_open_on(app, .Paths)
	case .Open_With:     act_open_with(app)
	case .Reveal:        act_reveal(app)
	case .Copy_Path:     act_copy_path(app)
	case .Settings:      settings_toggle(app)
	// (the sheet adds the toolkit's palette command itself)
	case .Shortcuts:     ui.shortcuts_sheet_open(&app.sheet, slice.enumerated_array(&ACTIONS), i18n.tr("Feuille's keys"))
	case .New_Window:    act_new_window(app)
	case .Minimize:      act_minimize(app)
	case .Maximize:      act_maximize(app)
	case .Full_Screen:   act_full_screen(app)
	case .Check_Updates: act_update_check(app)
	case .Update_Install: act_update_install(app)
	case .Update_Restart: leave_document(app, .Restart)
	case .About:         act_about(app)
	case .Website:       act_website(app)
	case .Report:        act_report(app)
	case .Changelog:     act_changelog(app)
	case .Settings_Folder: act_settings_folder(app)
	case .Version_Copy:  act_version_copy(app)
	case .Theme_Next:    act_theme_next(app)
	case .Theme_Previous: act_theme_previous(app)
	case .Density:       act_density(app)
	case .Animations:    act_animations(app)
	case .Text_Bigger:   act_text_bigger(app)
	case .Text_Smaller:  act_text_smaller(app)
	case .Text_Reset:    act_text_reset(app)
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

// A file to open from outside the open dialog (a drop, a second start, a recent PDF): an edited document asks first.
open_asked :: proc(app: ^App, path: string) {
	context.allocator = runtime.heap_allocator()
	delete(app.leave_path)
	app.leave_path = strings.clone(path)
	leave_document(app, .Open_File)
}

leave_now :: proc(app: ^App, next: Leave_Next) {
	switch next {
	case .None:
	case .Open_Dialog:
		app.settings_open = false
		ui.file_dialog(&app.main.state, .Open, {owner = app.main.win, title = i18n.tr("Open a PDF"), filters = PDF_FILTERS[:], all_files = true, remember_id = "open"}, open_chosen, app)
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
	sources:  Palette_Sources,   // `@` the pages, `/` the recent PDFs (palette_sources.odin)
}

// What action_enabled reads: when one moves, `disabled` is read again.
Palette_Key :: struct {
	revision: u64,
	selected: u64,
	settings: bool,
	pending:  Pending,
	opened:   bool,      // a document is shown
	recent:   u64,       // the memory's version
	updates:  [3]bool,   // an updater, an update on offer, one in place
}

palette_init :: proc(app: ^App) {
	if !app.headless { ui.palette_memory_open(&app.palette, &app.main.state, palette_choices_path()) }
	open :: proc(user: rawptr) { (^App)(user).settings_open = true }
	options :: proc(user: rawptr) -> prefs_page.Page_Options { return settings_options((^App)(user)) }
	prefs_page.palette_settings_add(&app.palette, &app.palette_state.settings, &app.prefs, &app.settings_page, options, open, app)
	palette_sources_add(app)
}

@(private = "file")
palette_give :: proc(app: ^App) {
	ps := &app.palette_state
	key := Palette_Key{
		app.snapshot != nil ? app.snapshot.revision : 0, app.selected, app.settings_open, app.pending, app.snapshot != nil,
		app.memory.version, {has_updater(app), update_available(app), update_installed(app)},
	}
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
