# Development

## Setup

```sh
git clone --recurse-submodules https://github.com/sachahjkl/feuille
cd feuille
nix develop        # the pinned Odin with wgpu-native, Rust (the toolkit's native library: text, PDF), the git hooks
```

Without Nix: Odin `dev-2026-11a` (`odin.version`), clang and lld, cargo, wgpu-native's static library in Odin's
`vendor/wgpu/lib` (`odin run ext/gui_toolkit/tools/tk -- fetch_wgpu`), fontconfig.

## feuilletool

Every step is a command of `tools/feuilletool`. `./build.sh` is its shortcut for `build`.

```sh
odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -keep-executable -- help
```

| Command | What it does |
|---|---|
| `build [release]` | the toolkit's native library (text, PDF) when its sources changed, then `build/feuille` (debug; `release`: optimised) |
| `test [names]` | the tests of `src` and the tool, with no window of the system |
| `check` | the changelog and the roadmap, the scopes, `odin check -vet` for this system, Windows and macOS and of the tool, the tests, a release build |
| `changelog new <type> <text>`, `check`, `preview` | a fragment of `changelog.d/`, their check, what the next version brings |
| `logo` | `assets/logo*.png`, `assets/feuille.ico` and `.project/image.png`, drawn by the toolkit's paint package |
| `notices [--check]` | `THIRD-PARTY-NOTICES`: the licences of the toolkit, its fonts and icons, Odin's core library, wgpu-native, the native library's crates (hayro among them); `check` checks it is up to date |
| `site build\|check\|card` | the site; `check` also checks that each system's browser is offered its own download |
| `i18n fr [-check]` | `i18n/fr.txt` from the code's texts |

`build`, `test` and `check` are gui_toolkit's (`toolbox.build_commands`). `GT=<folder>` builds against another checkout
of gui_toolkit.

## A change

- Comments and commit messages are in English. Comments say why.
- A change of design changes its intent file in `src/md` in the same commit.
- A change a person sees has its fragment in `changelog.d/`.
