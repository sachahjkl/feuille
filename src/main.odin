// feuille: open a PDF at once, arrange its pages, change its words. src/md/README.md says how it is built.
package feuille

import "core:fmt"
import "core:os"
import "gt:cli"
import host "gt:host"
import "gt:platform"

APP_VERSION :: "0.0.0"
APP_NAME    :: "feuille"
APP_TITLE   :: "Feuille"
APP_FOLDER  :: "FromentSoftware" + platform.USER_DIR_SEPARATOR + APP_TITLE

main :: proc() {
	cli.exit(run(os.args[1:]))
}

USAGE :: `feuille [file.pdf]: open a PDF, its signatures, annotations and form fields hidden
feuille version: the version`

run :: proc(args: []string) -> cli.Exit {
	path := ""
	for a in args {
		switch a {
		case "version", "--version":
			fmt.println(APP_VERSION)
			return .Done
		case "help", "-h", "--help":
			fmt.println(USAGE)
			return .Done
		}
		if path != "" {
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

	app := app_open({path = path})
	if app == nil {
		fmt.eprintln("feuille: no window could be opened")
		return .Failed
	}
	defer app_close(app)
	platform.show_window(app.main.win)
	for !platform.is_closed(app.main.win) {
		host.hosts_wait({&app.main})
		host.host_frame(&app.main)
	}
	return .Done
}
