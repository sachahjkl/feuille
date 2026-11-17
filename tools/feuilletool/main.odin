// feuilletool: the project's machinery, one program, whatever the shell.
//
//   odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -- <command>
//   (build.sh and build.bat are its shortcuts for `build`)
//
// What it needs is on the path: git, odin, cargo (the toolkit's text library). GT=<folder>: another checkout of
// gui_toolkit (its root, not its src).
package feuilletool

import changelog "gt:changelog"
import toolbox "gt:toolbox"

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
		// (only the icons feuille names are compiled in)
		features = {.Lucide_Subset},
	}
}

commands :: proc() -> []toolbox.Command {
	b := toolbox.build_commands(build_options())
	list := make([dynamic]toolbox.Command, context.temp_allocator)
	append(&list, b[0], b[1], b[2], changelog.command(project()), toolbox.logo_command(logo()))
	return list[:]
}

main :: proc() {
	toolbox.tool_main("feuilletool", commands(), toolbox.ROOT_MARK_DEFAULT)
}
