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

project :: proc() -> toolbox.Project {
	return {
		name = "feuille", repository = REPOSITORY, changelog = "CHANGELOG.md",
		title = "Feuille", description = "Open a PDF at once, arrange its pages, change its words.",
		publisher = "Froment Software", copyright = "Copyright (c) 2026 sachahjkl",
	}
}

commands :: proc() -> []toolbox.Command {
	list := make([dynamic]toolbox.Command, context.temp_allocator)
	append(&list, changelog.command(project()), toolbox.logo_command(logo()))
	return list[:]
}

main :: proc() {
	toolbox.tool_main("feuilletool", commands(), toolbox.ROOT_MARK_DEFAULT)
}
