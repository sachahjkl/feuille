# The window around the document

## Purpose

feuille is one of Froment Software's programs and looks and behaves as its siblings (papier, classeur): the toolkit's
machined finish, its own theme, its own title bar, every setting in the window, every command in a palette. A person
who knows one knows the others.

## Decisions

- Everything that is not the document is the toolkit's: the settings page (`prefs_page`), the palette, the keys' sheet,
  the crash bar, the updater, the licence page, the What's new page. feuille gives them its words and its table of
  actions (`src/actions.odin`), nothing more. A need they do not meet goes into the toolkit, not here.
- One table of actions: the title bar's tools, the keys, the palette and the sheet read it. A tool states its act name,
  so the palette's Shift+Enter shows the button.
- The theme "Feuille" is warm: the dark of a wood table, the paper of the light mode, the accent of the logo's leaf. The
  page itself is always white: the engine draws on white, and a PDF's colours are the PDF's.
- The masked opening is a preference (`view.form_layer`, off): a person who wants the layer at every open says so once.
  Ctrl+L changes it for the document shown only; the next document opens as the preference says.
- A licence supports the program and unlocks nothing. Everything is in the one version.
- Updates: the toolkit's updater, checked from the settings. Nothing updates by itself on Linux yet: no install is
  known (the toolkit's Install is Windows' setup), and a Nix copy is Nix's.

## The pictures

The README's and the site's pictures are the program's own frames: `src/shots_test.odin`, opt-in, in the headless
session (the software renderer, the fonts compiled in), on a sample form the tests' writer makes
(`src/fixture/sample.odin`). `feuilletool shots` makes them again after a change of the window.
