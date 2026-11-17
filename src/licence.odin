package feuille

// feuille's licence (gt:licence, gui_toolkit docs/licence.md): a signed key, checked on this computer with no network.
// A licence changes nothing of what feuille does: everything is in the one version, and the licence says who supports
// it. The settings show it on the toolkit's Licence page (prefs_page.Licence). The store's file is touched only in the
// page's tasks, never on the interface's thread.

import prefs_page "gt:prefs_page"
import feuille_licence "licence"

// Where a licence is bought: the site's pricing page.
PRICING_URL :: "https://feuille.froment.software/pricing/"

licence_init :: proc(app: ^App) {
	// (a debug build accepts the development pair: the tests and the pictures register with it; the tests keep it in
	// memory, the person's folder untouched)
	prefs_page.licence_init(&app.licence, &app.main.state, {
		store = {product = feuille_licence.PRODUCT, program = APP_FOLDER, memory = app.headless, accept_dev = ODIN_DEBUG},
		name = APP_TITLE, pricing_url = PRICING_URL, owner = app.main.win,
		logo = #load("../assets/logo_256.png"), vendor = "Froment Software",
	})
}

// After the chores have stopped: no task holds the store any more.
licence_destroy :: proc(app: ^App) { prefs_page.licence_end(&app.licence) }
