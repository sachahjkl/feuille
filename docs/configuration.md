# Configuration

feuille's settings are in its window (Ctrl+, or the gear), and in the file `~/.config/FromentSoftware/Feuille/prefs`,
one `name = value` a line. `feuille --pref name=value` overrides one for a run.

The look, the text, the scrolling, the input, the delays, the rendering, the keys, the messages, the language, the file
dialogs and the updates are gui_toolkit's standard settings: [its docs/settings.md](https://github.com/sachahjkl/gui_toolkit/blob/master/docs/settings.md).
`general.menu` (in the applications menu) and `general.autostart` (started with the session) show once this copy is the
installed one ([desktop.md](desktop.md)): they act on that install only. `update.auto` updates the installed copy by
itself.

feuille's own:

| Name | Default | What it does |
|---|---|---|
| `general.reopen_last` | `true` | With no file given, Feuille opens the last PDF again, at the page and the zoom it showed. |
| `view.form_layer` | `false` | Draw the signatures, annotations and form fields when a PDF opens. Off, only the pages' own content is drawn; Ctrl+L shows the layer for one document. |
| `window.width` | `900` | The window's width at its first start, in logical pixels. |
| `window.height` | `1000` | The window's height at its first start, in logical pixels. |

What feuille remembers beside the settings is in `~/.local/state/FromentSoftware/Feuille/` (Windows:
`%LOCALAPPDATA%\FromentSoftware\Feuille\state\`): `documents.txt`, the recent PDFs with the page each showed last;
`zooms.txt`, each one's zoom; `file_dialogs.txt`, `views.txt` and `palette_choices.txt`, the dialogs' and the palette's
memory.
