#+build !linux
package pdf

// The other systems' loader comes with the Windows layer of the roadmap (LoadLibrary and GetProcAddress fill the same
// table). Until then init says the engine is missing.

@(private)
load_library :: proc(a: ^Api) -> bool { return false }
