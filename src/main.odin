// feuille: open a PDF at once, arrange its pages, put text on them. src/md/README.md says how it is built.
package feuille

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "gt:cli"
import png "gt:png"
import thumbnail "thumbnail"
import host "gt:host"
import instance "gt:instance"
import "gt:platform"
import prefs_page "gt:prefs_page"
import "gt:process"
import setup "gt:setup"

APP_VERSION :: "0.12.1"
APP_NAME    :: "feuille"
APP_TITLE   :: "Feuille"
APP_FOLDER  :: "FromentSoftware" + platform.USER_DIR_SEPARATOR + APP_TITLE

main :: proc() {
	cli.exit(run(os.args[1:]))
}

USAGE :: `feuille: a PDF reader that nothing blocks

  feuille [file.pdf]     a window on this PDF, its signatures, annotations and form fields hidden; a running feuille
                         opens it in its own window
  feuille --setup        the window, the install's dialog open: install feuille for you, repair or upgrade the
                         install, or uninstall it (also in the settings: Installation)
  feuille --install      install this copy for you: the program, its launcher in the applications menu, its icons,
                         feuille on the PATH
  feuille --uninstall    take the install away (your settings stay)
  feuille --status       what is installed, and whether feuille runs (exit 0 installed, 2 to repair, 1 not installed)
  feuille --thumbnail <file.pdf> <out.png> <size>
                         the PDF's first page as a picture of at most size x size (the file managers' thumbnails)
  feuille version        the version
  --pref name=value      a preference for this run only
`

run :: proc(given: []string) -> cli.Exit {
	// (a file manager's thumbnailer: no window, no instance, no settings; it may run many at once)
	if len(given) > 0 && given[0] == "--thumbnail" { return thumbnail_command(given[1:]) }
	// (--install, --uninstall and --status: no window; --setup: the window, the install's dialog open)
	cmd, args := setup.command_of(given)
	if setup.command_alone(cmd) { return setup.command_run(cmd, setup_options(), process.console_write) }
	setup_asked := cmd == .Setup
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
			fmt.print(USAGE)
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
			fmt.eprint(USAGE)
			return .Usage
		}
		// (absolute: the worker reads it whatever the working folder becomes, and a second start hands it to the first,
		// which runs in another folder)
		abs, err := os.get_absolute_path(a, context.allocator)
		path = err == nil ? abs : a
	}

	// One window per person: a second start hands its file to the first, which opens it, and ends. Its launcher's
	// activation token goes with it: the first's window comes up with it on Wayland.
	message := app_message_make(platform.activation_token_from_env(context.temp_allocator), path, setup_asked)
	outcome, owner := instance.acquire({name = app_instance_name()}, transmute([]u8)message)
	if outcome == .Forwarded { return .Done }

	p := host.program_start({name = APP_NAME, folder = APP_FOLDER, version = APP_VERSION})
	context.logger = p.logger
	defer host.program_end(&p)

	app := app_open({path = path, pref_args = prefs[:], last_crash = p.last_crash})
	if app == nil {
		if outcome == .First { instance.owner_stop(&owner) }
		fmt.eprintln("feuille: no window could be opened")
		return .Failed
	}
	server: ^instance.Server
	if outcome == .First { server = instance.serve_start(owner, app_message, app) }
	platform.show_window(app.main.win)
	// (the install read on a task; offered at the start on Windows only: Linux has Nix or `feuille --install`)
	prefs_page.install_offer(&app.install, &app.main.state, offer = SETUP_AT_START && !setup_asked)
	if setup_asked { prefs_page.install_open(&app.install) }
	for !app.quit && !platform.is_closed(app.main.win) {
		host.hosts_wait({&app.main})
		app_step(app)
	}
	// (the instance let go before the end: a restart, an update or the installed copy starts after it, and owns it)
	instance.serve_stop(server)
	app_close(app)
	return .Done
}

// `--thumbnail <file.pdf> <out.png> <size>`: the freedesktop thumbnailer's command (%i %o %s), the PNG of the first page.
thumbnail_command :: proc(args: []string) -> cli.Exit {
	if len(args) != 3 { fmt.eprint(USAGE); return .Usage }
	size, size_ok := strconv.parse_int(args[2])
	if !size_ok || size <= 0 || size > THUMBNAIL_MAX { fmt.eprint(USAGE); return .Usage }
	data, err := os.read_entire_file_from_path(args[0], context.allocator)
	if err != nil { fmt.eprintfln("feuille: %s cannot be read", args[0]); return .Failed }
	rgba, w, h, ok := thumbnail.render(data, size)
	if !ok { fmt.eprintfln("feuille: %s has no page to show", args[0]); return .Failed }
	if os.write_entire_file(args[1], png.encode(rgba, w, h)) != nil { fmt.eprintfln("feuille: %s cannot be written", args[1]); return .Failed }
	return .Done
}

// The largest thumbnail asked (the spec's "xx-large" is 1024).
THUMBNAIL_MAX :: 2048
