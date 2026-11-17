// feuille: open a PDF at once, arrange its pages, change its words. src/md/README.md says how it is built.
package feuille

import "core:fmt"
import "core:os"
import "core:strings"
import "gt:cli"
import host "gt:host"
import "gt:platform"

APP_VERSION :: "0.1.0"
APP_NAME    :: "feuille"
APP_TITLE   :: "Feuille"
APP_FOLDER  :: "FromentSoftware" + platform.USER_DIR_SEPARATOR + APP_TITLE

main :: proc() {
	cli.exit(run(os.args[1:]))
}

USAGE :: `feuille [file.pdf] [--pref name=value]...
  Opens a PDF with its signatures, annotations and form fields hidden.
feuille version   the version`

run :: proc(args: []string) -> cli.Exit {
	path := ""
	prefs := make([dynamic]string, context.temp_allocator)
	for i := 0; i < len(args); i += 1 {
		a := args[i]
		switch {
		case a == "version" || a == "--version":
			// (the program's name and its version: what the toolkit's console launcher check expects)
			fmt.println(APP_NAME, APP_VERSION)
			return .Done
		case a == "help" || a == "-h" || a == "--help":
			fmt.println(USAGE)
			return .Done
		case a == "--pref" && i + 1 < len(args):
			i += 1
			append(&prefs, "--pref", args[i])
			continue
		case strings.has_prefix(a, "--pref="):
			append(&prefs, a)
			continue
		}
		if path != "" || strings.has_prefix(a, "-") {
			fmt.eprintln(USAGE)
			return .Usage
		}
		// (absolute: the worker reads it whatever the working folder becomes)
		abs, err := os.get_absolute_path(a, context.allocator)
		path = err == nil ? abs : a
	}

	p := host.program_start({name = APP_NAME, folder = APP_FOLDER, version = APP_VERSION})
	context.logger = p.logger
	defer host.program_end(&p)

	app := app_open({path = path, pref_args = prefs[:], last_crash = p.last_crash})
	if app == nil {
		fmt.eprintln("feuille: no window could be opened")
		return .Failed
	}
	platform.show_window(app.main.win)
	for !app.quit && !platform.is_closed(app.main.win) {
		host.hosts_wait({&app.main})
		app_step(app)
	}
	app_close(app)
	return .Done
}
