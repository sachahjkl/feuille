package feuilletool

// build, test, check: the toolkit's (toolbox.build_commands), the same steps on a laptop and in the CI.

import changelog "gt:changelog"
import toolbox "gt:toolbox"

// The packages that have tests. One thread: the program's tests share one interface.
@(rodata) TESTS := [?]toolbox.Test_Package{{path = "src", one_thread = true}, {path = "src/thumbnail"}}

build_options :: proc() -> toolbox.Build_Options {
	p := project()
	// (notices: the archive ships THIRD-PARTY-NOTICES, so check keeps it up to date)
	return {project = p, changelog_command = changelog.command(p), tests = TESTS[:], catalogues = I18N, notices = true}
}
