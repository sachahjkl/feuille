package feuille

// The preferences: one registry (gt:config). The user's file is $XDG_CONFIG_HOME/FromentSoftware/Feuille/prefs;
// `--pref name=value` overrides it for one run. The look, the text, the scrolling, the input, the delays, the rendering,
// the keys, the updates and the messages are the toolkit's standard settings (prefs_page.standard_register); feuille adds
// its own after them. Each one here has its line in docs/configuration.md (settings_test.odin checks it).

import "core:strings"
import config "gt:config"
import i18n "gt:i18n"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:ui"

LAYER_PREF :: "view.form_layer"
REOPEN_PREF :: "general.reopen_last"

// feuille's identity in the standard settings: its theme and its name; the rest is the toolkit's.
@(private = "file")
standard_defaults :: proc() -> prefs_page.Standard_Defaults {
	d := prefs_page.STANDARD_DEFAULTS
	d.theme, d.app_name = "Feuille", APP_TITLE
	return d
}

// Registered in English before the language is known: the settings page translates them where it shows them.
PREF_DEFS := [?]config.Def{
	{name = REOPEN_PREF, title = i18n.later("Reopen the last PDF"), description = i18n.later("With no file given, Feuille opens the last PDF again, at the page and the zoom it showed."), kind = .Bool, default = {b = true}, tags = {"recent", "start", "restore", "session"}},
	{name = LAYER_PREF, title = i18n.later("Form layer at open"), description = i18n.later("Draw the signatures, annotations and form fields when a PDF opens. Off: only the pages' own content is drawn, and nothing on the page can block it; Ctrl+L shows the layer for one document."), kind = .Bool, default = {b = false}, tags = {"signature", "annotation", "field", "form", "acrobat"}},
	{name = "window.width", title = i18n.later("Width"), description = i18n.later("The window's width at its first start, in logical pixels."), kind = .Int, default = {i = 900}, min = 320, max = 6000, bounded = true, value_kind = .Length, unit = .Pixel, tags = {"size", "window"}},
	{name = "window.height", title = i18n.later("Height"), description = i18n.later("The window's height at its first start, in logical pixels."), kind = .Int, default = {i = 1000}, min = 240, max = 6000, bounded = true, value_kind = .Length, unit = .Pixel, tags = {"size", "window"}},
}

// The values the program reads, copied out of the registry (prefs_read).
Settings :: struct {
	layer:        bool,
	reopen_last:  bool,
	look:         prefs_page.Appearance,
	size:         [2]int,
	system_title: bool,
	messages:     ui.Announce_Mode,
}

prefs_file :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.Config, APP_FOLDER, context.temp_allocator), "/prefs"}, allocator)
}

// The user's own themes, beside the preferences (prefs_page.Themes_File).
themes_file :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.Config, APP_FOLDER, context.temp_allocator), "/themes.txt"}, allocator)
}

// Where the palette remembers what the person chose, and the views how each dialog is shown.
palette_choices_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/palette_choices.txt"}, allocator)
}

views_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/views.txt"}, allocator)
}

// Where the file dialogs remember their folder, their size and their recent folders (ui.file_dialog_memory).
file_dialogs_path :: proc(allocator := context.temp_allocator) -> string {
	return strings.concatenate({platform.user_dir(.State, APP_FOLDER, context.temp_allocator), "/file_dialogs.txt"}, allocator)
}

// The registry, the user's file read in unless `read_file` is false (the tests), then `args`' --pref. Returns the
// arguments that are not preferences, and what was wrong.
prefs_open :: proc(p: ^config.Prefs, args: []string, read_file := true, descriptions := context.allocator) -> (rest: [dynamic]string, problems: [dynamic]string) {
	p^ = config.prefs_make()
	prefs_page.standard_register(p, prefs_page.STANDARD_ALL, standard_defaults(), descriptions)
	config.register(p, PREF_DEFS[:])
	prefs_page.changelog_register(p)   // (the version last started: What's new after an update)
	file_problems: [dynamic]string
	if read_file { _, file_problems = config.load_file(p, prefs_file(), .User) }
	rest, problems = config.apply_args(p, args, context.temp_allocator)
	append(&problems, ..file_problems[:])
	return
}

prefs_read :: proc(p: ^config.Prefs, allocator := context.allocator) -> (s: Settings) {
	s.layer = config.bool_of(p, LAYER_PREF)
	s.reopen_last = config.bool_of(p, REOPEN_PREF)
	s.look = prefs_page.appearance_read(p, allocator)
	s.system_title = config.bool_of(p, prefs_page.SYSTEM_TITLE_PREF)
	s.size = {int(config.int_of(p, "window.width")), int(config.int_of(p, "window.height"))}
	s.messages = prefs_page.announce_mode(p)
	return
}

settings_free :: proc(s: ^Settings) {
	prefs_page.appearance_destroy(&s.look)
	s^ = {}
}
