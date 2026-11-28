# The window around the document

## Purpose

feuille is one of Froment Software's programs and looks and behaves as its siblings (papier, classeur): the toolkit's
machined finish, its own theme, its own title bar, every setting in the window, every command in a palette. A person
who knows one knows the others.

## Decisions

- Everything that is not the document is the toolkit's: the settings page (`prefs_page`), the palette, the keys' sheet,
  the About modal (`ui.about_modal`, with its built-in What's new button and diagnostics), the crash bar, the updater,
  the licence page, the What's new page. feuille gives them its words and its table of actions (`src/actions.odin`),
  nothing more. A need they do not meet goes into the toolkit, not here.
- One table of actions: the title bar's tools, the keys, the palette, the sheet and the context menus read it. A tool
  states its act name, so the palette's Shift+Enter shows the button.
- The suite's program commands, by the suite's ids and keys (`src/program_actions.odin`): New window, Minimize
  (Alt+F9), Maximize (Alt+F10), Full screen (F11), the updates, About, the website, Report a problem, Release notes, the
  settings' folder, Copy the version, the themes, Compact rows, Animations, the text's size. One exception: the default
  text size is Ctrl+Alt+0, because Ctrl+0 is the pages' zoom back to the width (the zoom zone's own key).
- The title bar ends with the toolkit's window buttons (minimise, maximise or restore, close); close asks as Quit does
  when the document has unsaved edits. The system's title bar has its own.
- The palette's own sources (`src/palette_sources.odin`): `@` the pages ("Page 3 of 12", a number goes to that page),
  `/` the recent PDFs ([memory.md](memory.md)). Ctrl+G and Ctrl+Shift+O open the palette on them.
- A right click on a page or a thumbnail selects it and opens its menu (`src/menus.odin`): the page's edits, then the
  file's acts (Copy the path, Show in folder, Open with), and the system's shell actions for the file
  (`ui.Shell_Menu`). Both lists are read off the interface thread when the menu opens.
- The theme "Feuille" is warm: the dark of a wood table, the paper of the light mode, the accent of the logo's leaf. The
  page itself is always white: the engine draws on white, and a PDF's colours are the PDF's.
- The masked opening is a preference (`view.form_layer`, off): a person who wants the layer at every open says so once.
  Ctrl+L changes it for the document shown only; the next document opens as the preference says.
- A licence supports the program and unlocks nothing. Everything is in the one version.
- Updates: the toolkit's updater. The installed copy updates by itself (`update.auto`, the install read by
  `prefs_page.Install`, on Linux and Windows); another copy updates when the settings' Check now asks; a Nix copy is
  Nix's. The install itself is [desktop.md](desktop.md).
- The file dialogs remember their folder and size (`ui.file_dialog_memory`); `general.file_dialog` chooses the system's
  or the toolkit's, as in every program of the suite.

## The pictures

The README's and the site's pictures are the program's own frames: `src/shots_test.odin`, opt-in, in the headless
session (the software renderer, the fonts compiled in), on a sample form the tests' writer makes
(`src/fixture/sample.odin`). `feuilletool shots` makes them again after a change of the window.
