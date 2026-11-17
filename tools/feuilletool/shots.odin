package feuilletool

// shots: the pictures of the README and the site. They are the program's own frames, made by src/shots_test.odin in
// the program's headless session (the software renderer, the fonts compiled in: the same pixels on every machine), on
// the tests' sample form. Written to docs/screenshots, then copied to site/img for the site.

import "core:fmt"
import "core:os"
import "core:path/filepath"
import cli "gt:cli"
import toolbox "gt:toolbox"

SHOTS_OUT  :: "docs/screenshots"
SHOTS_SITE :: "site/img"

run_shots :: proc(args: []string) -> cli.Exit {
	out := SHOTS_OUT
	for i := 0; i < len(args); i += 1 {
		if args[i] == "--out" && i + 1 < len(args) { i += 1; out = args[i]; continue }
		fmt.eprintfln("shots: what is %s?", args[i])
		return .Usage
	}
	_ = os.make_directory_all(out)
	abs, err := os.get_absolute_path(out, context.temp_allocator)
	if err != nil { fmt.eprintfln("shots: %s cannot be made", out); return .Failed }
	o := build_options()
	if !toolbox.build_native(o.project) { return .Failed }
	extra := []string{
		fmt.tprintf("-define:FEUILLE_SHOTS=%s", abs), "-define:ODIN_TEST_NAMES=feuille.shots", "-define:ODIN_TEST_THREADS=1",
		"-out:build/test_shots",
	}
	if !toolbox.run(toolbox.odin_command(o.project, "test", "src", extra), {echo = true}) { return .Failed }
	// (the site shows the same pictures)
	if out == SHOTS_OUT {
		_ = os.make_directory_all(SHOTS_SITE)
		files, _ := os.read_all_directory_by_path(out, context.temp_allocator)
		for f in files {
			if filepath.ext(f.name) != ".png" { continue }
			data, rerr := os.read_entire_file_from_path(f.fullpath, context.temp_allocator)
			if rerr != nil { continue }
			_ = os.write_entire_file(fmt.tprintf("%s/%s", SHOTS_SITE, f.name), data)
		}
	}
	fmt.printfln("shots: %s", out)
	return .Done
}
