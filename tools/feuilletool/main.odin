// feuilletool: the project's machinery, one program, whatever the shell.
//
//   odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -- <command>
//   (build.sh and build.bat are its shortcuts for `build`)
//
// What it needs is on the path: git, odin, cargo (the toolkit's text library), tar; gh for what is published; cwebp for
// the site. GT=<folder>: another checkout of gui_toolkit (its root, not its src).
package feuilletool

import changelog "gt:changelog"
import cli "gt:cli"
import release "gt:release"
import toolbox "gt:toolbox"
import feuille_licence "../../src/licence"
import feuille_update "../../src/update"

REPOSITORY :: "https://github.com/sachahjkl/feuille"
when ODIN_OS == .Windows {
	PROGRAM :: "build/feuille.exe"
} else {
	PROGRAM :: "build/feuille"
}

project :: proc() -> toolbox.Project {
	return {
		name = "feuille", repository = REPOSITORY, changelog = "CHANGELOG.md",
		version_file = "src/main.odin", version_line = "APP_VERSION :: ", program = PROGRAM,
		title = "Feuille", description = "Open a PDF at once, arrange its pages, change its words.",
		publisher = "Froment Software", copyright = "Copyright (c) 2026 sachahjkl",
		// (only the icons feuille names are compiled in; the DevTools endpoint in a release too, for the live test)
		features = {.Lucide_Subset, .Devtools},
	}
}

// The `licence` and `paddle` commands: feuille's licence (src/licence), its development pair, its Paddle catalogue.
LICENCE_TOOL :: toolbox.Licence_Tool{
	product  = feuille_licence.PRODUCT,
	// (the development pair's private key, public on purpose: "feuille-dev-licence-test-seed-1!")
	dev_seed = "ZmV1aWxsZS1kZXYtbGljZW5jZS10ZXN0LXNlZWQtMSE",
	hint     = "Open this file with Feuille (Settings > General > Licence, Choose a file), or paste the key there.",
	paddle   = {name = "Feuille User License", description = "A personal, perpetual licence of Feuille, the PDF reader that nothing blocks.", amounts = "supporter=1500", currency = "EUR"},
}

// What goes beside the program in a release's archive: the file, and its name there. PDFium goes with it: the program
// loads it from its own folder (pdfium.odin).
when ODIN_OS == .Windows {
	PDFIUM_FILE :: "pdfium.dll"
} else {
	PDFIUM_FILE :: "libpdfium.so"
}
@(rodata)
RELEASE_FILES := [?][2]string{
	{"README.md", "README.md"}, {"LICENSE", "LICENSE"}, {"CHANGELOG.md", "CHANGELOG.md"},
	{"ext/gui_toolkit/src/lucide/LICENSE.txt", "LUCIDE-LICENSE.txt"},
	{PDFIUM_LIBRARY, PDFIUM_FILE}, {PDFIUM_LICENCE, "PDFIUM-LICENSE.txt"},
}

// feuille's texts, from its code, into i18n/<language>.txt (the program embeds them: src/app.odin).
I18N := toolbox.I18n_Catalogues{dirs = {"src"}, folder = "i18n"}

commands :: proc() -> []toolbox.Command {
	p := project()
	b := toolbox.build_commands(build_options())
	r := release.commands({project = p, dist = "build/dist", files = RELEASE_FILES[:], check = proc() -> cli.Exit { return toolbox.ended(toolbox.program_check(build_options())) }, update = feuille_update.PRODUCT})
	l := toolbox.licence_commands(LICENCE_TOOL)
	list := make([dynamic]toolbox.Command, context.temp_allocator)
	append(&list,
		b[0], b[1], b[2],
		toolbox.Command{name = "shots", usage = "[--out folder]: the pictures of the README and the site, the program's own frames, headless", run = run_shots},
		toolbox.logo_command(logo()),
		r[0], r[1], r[2],
		toolbox.Command{name = "update", usage = "keygen <file> | pubkey | manifest <program> <version> - <out> | verify <manifest> -: feuille's update key and manifests", run = proc(args: []string) -> cli.Exit { return toolbox.update_command(feuille_update.PRODUCT, args) }},
		changelog.command(p),
		toolbox.i18n_command(I18N),
		site_command(),
		l[0], l[1],
	)
	return list[:]
}

main :: proc() {
	toolbox.tool_main("feuilletool", commands(), toolbox.ROOT_MARK_DEFAULT)
}
