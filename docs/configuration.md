# Configuration

feuille's settings are in its window (Ctrl+, or the gear), and in the file `~/.config/FromentSoftware/Feuille/prefs`,
one `name = value` a line. `feuille --pref name=value` overrides one for a run.

The look, the text, the scrolling, the input, the delays, the rendering, the keys, the messages, the language and the
updates are gui_toolkit's standard settings: [its docs/settings.md](https://github.com/sachahjkl/gui_toolkit/blob/master/docs/settings.md).

feuille's own:

| Name | Default | What it does |
|---|---|---|
| `view.form_layer` | `false` | Draw the signatures, annotations and form fields when a PDF opens. Off, only the pages' own content is drawn; Ctrl+L shows the layer for one document. |
| `window.width` | `900` | The window's width at its first start, in logical pixels. |
| `window.height` | `1000` | The window's height at its first start, in logical pixels. |
