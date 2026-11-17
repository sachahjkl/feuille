# feuille

A PDF reader and page editor, in Odin, on the `ext/gui_toolkit` submodule (collection `gt`). Linux first (Wayland and
X11); Windows later, through the toolkit. It opens a document without its interactive layer (signatures, annotations,
form fields), arranges its pages, edits its words, and saves a copy. One version, everything in it.

Read first: [README.md](README.md), [src/md/README.md](src/md/README.md) (the intent), [ROADMAP.md](ROADMAP.md),
[docs/development.md](docs/development.md).

## Build and test

Every step is a command of `tools/feuilletool` (`help` lists them):

    odin run tools/feuilletool -collection:gt=ext/gui_toolkit/src -out:build/feuilletool -keep-executable -- <command>

- `build [release]` builds `build/feuille` (`build.sh` and `build.bat` are shortcuts).
- `test [names]`: the tests of `src`, `src/pdf` and the tool, headless. `check`: the changelog and the roadmap, the
  scopes, `odin check -vet` for this system, Windows and macOS, the tests, a release build.
- `changelog new|check|preview`, `logo`.
- Linux: `nix develop` first (`flake.nix`: the pinned Odin, PDFium, Rust, the hooks).

## Rules

- The interface's thread never waits. No disk, network, process or engine call runs there, not even a `stat`. One
  worker owns the document: it loads, renders, edits and saves; its results come back with `ui.post`. A frame does no
  work in proportion to the page count: the layout is computed when the document changes, and kept.
- The interactive layer is hidden by default: the render draws no annotation, widget or signature appearance unless the
  person asks for them. No form environment is ever initialised.
- Saving writes a copy. The original is never overwritten without a confirmation.
- The PDF engine is `src/pdf`. It moves to gui_toolkit (`gt:pdf`) when a second program needs it. What more than one
  program needs goes in gui_toolkit, generic, with its docs, test and changelog fragment; feuille then points to the
  toolkit's new commit.
- A preference is a `config.Def` in `src/settings.odin` with its line in `docs/configuration.md`.
- Tests never read or write the person's files or desktop: the tests make their PDFs (`src/fixture`),
  and the window is headless.
- Automation is a command of `tools/feuilletool`, never a shell, batch, PowerShell, Python or Node script.
- Comments and commit messages are in English. Comments say why.
- Commits: author and committer `sachahjkl <sacha@sacha.house>`, no attribution trailer, no session link.

## Changelog

- `CHANGELOG.md` follows Keep a Changelog and semantic versioning. It is never edited by hand.
- A change a person sees is one fragment in `changelog.d/` (its README says the format), written by
  `feuilletool changelog new <type> <text>`, in the same commit as the change.
- `feuilletool ship` assembles the fragments into the version's section; `feuilletool check` checks the fragments and
  the file.

## Roadmap

- `ROADMAP.md`, beside `CHANGELOG.md`, holds feuille's planned work: `# Roadmap`, then `## Now`, `## Next` and
  `## Later`, each a list. An optional `## Maybe` comes last. Each entry starts with a bold summary, then one or two
  sentences on what it gives the user. No dates, no front matter.
- When a work is done, remove its entry in the same commit as its changelog fragment.
- Work that touches several programs goes in the roadmap of gui_toolkit.
- `feuilletool check` checks its format with the changelog's.

## Intent

This project follows <https://srcmd.org>, with the Markdown in `src/md`. Read `src/md/README.md` first.

- Change the intent first, then derive the code and the tests. A change of design changes its intent file in the same
  commit.
- Keep there what the code does not show: the purpose, the decisions, the refused alternatives, the subtle points.
- `src/md/README.md` lists every other file of the folder in its `## File Index`.
- The user's documentation and the developer's how-to stay in `docs/`; `src/md` links to them.

## Key prompts

Apply these to every task, before you write code:

- "Exercise abstract thinking when considering this task."
- "Reduce this problem to its irreducible constraints and rebuild it from zero."
- "What would a principal architect immediately rewrite before even starting this?"
- "Design the single test that breaks this design on day one."
- "What higher-level abstraction would make this entire problem disappear?"
- "Find all of the implicit state machines in my app."
