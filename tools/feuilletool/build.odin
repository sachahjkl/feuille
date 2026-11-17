package feuilletool

// build, test, check: the toolkit's (toolbox.build_commands), the same steps on a laptop and in the CI.

import changelog "gt:changelog"
import toolbox "gt:toolbox"

// The packages that have tests. One thread each: the engine has one thread at a time (src/pdf's claim), and the
// program's tests share one interface.
@(rodata) TESTS := [?]toolbox.Test_Package{{path = "src", one_thread = true}, {path = "src/pdf", one_thread = true}}

build_options :: proc() -> toolbox.Build_Options {
	p := project()
	// (notices: the archive ships THIRD-PARTY-NOTICES, so check keeps it up to date)
	return {project = p, changelog_command = changelog.command(p), tests = TESTS[:], catalogues = I18N, prepare = pdfium_prepare, notices = true}
}
