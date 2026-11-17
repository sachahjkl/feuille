package feuille

// Updates: gui_toolkit's (prefs_page.updates_*, gt:update's Updater). It checks feuille's latest release a while after
// the start and then every day, downloads the program it names, checks it against its signed manifest (src/update) and
// puts it in place of this one; the new feuille runs at the next start (the settings' Restart now, or the next time).
// Only the installed copy does it by itself (update.auto; `feuille --install` or the Setup installs it, on Linux and
// Windows): a build, or a copy run where it was unpacked, is updated when the settings' Check now asks. A copy from the
// Nix store is left to Nix (the Updater says so).

import "base:runtime"
import "core:strings"
import "gt:host"
import prefs_page "gt:prefs_page"
import update "gt:update"
import feuille_update "update"

updates_init :: proc(app: ^App) {
	prefs_page.updates_start(&app.updates, {
		product = feuille_update.PRODUCT, repository = "sachahjkl/feuille", version = APP_VERSION,
		prefs = &app.prefs, install = &app.install, state = &app.main.state, window = app.main.win,
	})
}

// At each turn of the loop: what changed is said.
app_updates_follow :: proc(app: ^App) {
	changed, st := prefs_page.updates_follow(&app.updates)
	if changed {
		host.host_settle(&app.main)
		if words, _ := update.notice(st); words != "" { say(app, "%s", words) }
	}
}

// The program again once this one has ended: an update put in place, or Restart asked. The file is the one read at the
// start: the new program is in its place.
app_restart :: proc(app: ^App) {
	context.allocator = runtime.heap_allocator()   // (app_close frees it)
	delete(app.launch_after)
	app.launch_after = strings.clone(app.exe)
	app.quit = true
}
