package feuille

// Updates: gui_toolkit's (prefs_page.updates_*, gt:update's Updater). It checks feuille's latest release, downloads the
// program it names, checks it against its signed manifest (src/update) and puts it in place of this one. No install is
// known on Linux yet (prefs_page.Install is Windows' setup): the settings' Check now asks, nothing updates by itself. A
// copy from the Nix store is left to Nix.

import "core:fmt"
import "gt:host"
import process "gt:process"
import prefs_page "gt:prefs_page"
import update "gt:update"
import feuille_update "update"

updates_init :: proc(app: ^App) {
	prefs_page.updates_start(&app.updates, {
		product = feuille_update.PRODUCT, repository = "sachahjkl/feuille", version = APP_VERSION,
		prefs = &app.prefs, state = &app.main.state, window = app.main.win,
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

// The program again once this one has ended: an update put in place, or Restart asked.
app_restart :: proc(app: ^App) {
	delete(app.launch_after)
	app.launch_after = fmt.aprintf("%s", process.executable_path())
	app.quit = true
}
