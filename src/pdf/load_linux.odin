#+build linux
package pdf

// libpdfium.so with dlopen: the one beside the program first (a release's archive carries it), then the system's library
// path (the flake's shell and package). The handle is never closed: the engine lives as long as the process.

import "core:path/filepath"
import "core:strings"
import "core:sys/posix"

@(private)
load_library :: proc(a: ^Api) -> bool {
	sym :: proc(h: rawptr, name: cstring) -> rawptr { return posix.dlsym(posix.Symbol_Table(h), name) }
	for name in library_candidates() {
		h := posix.dlopen(name, posix.RTLD_LOCAL + {.NOW})
		if h == nil { continue }
		if api_fill(a, rawptr(h), sym) { return true }
		posix.dlclose(h)
		a^ = {}
	}
	return false
}

// The library beside the executable (its real path: /proc/self/exe), then the bare name for the system's search.
@(private = "file")
library_candidates :: proc() -> []cstring {
	out := make([dynamic]cstring, context.temp_allocator)
	buf: [4096]u8
	if n := posix.readlink("/proc/self/exe", raw_data(buf[:]), len(buf) - 1); n > 0 {
		dir := filepath.dir(string(buf[:n]))
		append(&out, strings.clone_to_cstring(strings.concatenate({dir, "/libpdfium.so"}, context.temp_allocator), context.temp_allocator))
	}
	append(&out, "libpdfium.so")
	return out[:]
}
