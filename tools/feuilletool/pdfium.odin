package feuilletool

// PDFium beside the program: build/libpdfium.so or build/pdfium.dll, which the program loads from its own folder first
// (src/pdf). A build, a test and a package find it there; a release's archive carries it with its licence. Where it comes
// from: $PDFIUM_LIB when set (the flake's shell and package give the flake's library: no network in Nix's sandbox),
// else the pinned archive of bblanchon/pdfium-binaries, the same version as the flake's, checked by its SHA-256.

import "core:fmt"
import "core:os"
import toolbox "gt:toolbox"

PDFIUM_TAG :: "chromium%2F8152"
PDFIUM_DIR :: "build/pdfium"   // the archive and what is taken out of it

when ODIN_OS == .Windows {
	PDFIUM_ARCHIVE :: "pdfium-win-x64.tgz"
	PDFIUM_SHA256  :: "cee2b0e9990bc67c0721774932961b9dbf2766046c10eec925acd4cfba6fdfe3"
	PDFIUM_MEMBER  :: "bin/pdfium.dll"
	PDFIUM_LIBRARY :: "build/pdfium.dll"
} else {
	PDFIUM_ARCHIVE :: "pdfium-linux-x64.tgz"
	PDFIUM_SHA256  :: "384ab5c51882408a143a21f9c14dcd2caf1f75280ae41c554d0489b46c3dba9f"
	PDFIUM_MEMBER  :: "lib/libpdfium.so"
	PDFIUM_LIBRARY :: "build/libpdfium.so"
}
// The licence that goes with it in an archive.
PDFIUM_LICENCE :: PDFIUM_DIR + "/LICENSE"

// Build_Options.prepare: the library in place before an odin build or test.
pdfium_prepare :: proc(_: toolbox.Project) -> bool {
	_ = os.make_directory_all(PDFIUM_DIR)
	if from := os.get_env("PDFIUM_LIB", context.temp_allocator); from != "" {
		return copy_file(from, PDFIUM_LIBRARY)
	}
	archive := fmt.tprintf("%s/%s", PDFIUM_DIR, PDFIUM_ARCHIVE)
	url := fmt.tprintf("https://github.com/bblanchon/pdfium-binaries/releases/download/%s/%s", PDFIUM_TAG, PDFIUM_ARCHIVE)
	if why := toolbox.download_pinned(url, archive, PDFIUM_SHA256, quiet = true); why != "" {
		fmt.eprintfln("pdfium: %s", why)
		return false
	}
	// (tar: GNU's on Linux, bsdtar on Windows 10 and later; the archive is checked, so taking its files out again is safe)
	if !os.exists(PDFIUM_LICENCE) || !os.exists(fmt.tprintf("%s/%s", PDFIUM_DIR, PDFIUM_MEMBER)) {
		if !toolbox.run({"tar", "-xzf", archive, "-C", PDFIUM_DIR, PDFIUM_MEMBER, "LICENSE"}) { return false }
	}
	return copy_file(fmt.tprintf("%s/%s", PDFIUM_DIR, PDFIUM_MEMBER), PDFIUM_LIBRARY)
}

// `to` as `from`, written only when it differs (a running test may hold the old one open on Windows).
@(private = "file")
copy_file :: proc(from, to: string) -> bool {
	data, err := os.read_entire_file_from_path(from, context.temp_allocator)
	if err != nil {
		fmt.eprintfln("pdfium: %s cannot be read", from)
		return false
	}
	if old, oerr := os.read_entire_file_from_path(to, context.temp_allocator); oerr == nil && string(old) == string(data) { return true }
	if os.write_entire_file(to, data) != nil {
		fmt.eprintfln("pdfium: %s cannot be written", to)
		return false
	}
	return true
}
