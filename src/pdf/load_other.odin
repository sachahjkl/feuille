#+build !linux
#+build !windows
package pdf

// macOS has no loader yet: init says the engine is missing, and the program says so.

@(private)
load_library :: proc(a: ^Api) -> bool { return false }
