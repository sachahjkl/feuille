# Signature: a name signed on a page

## Purpose

Sign a document that has no signature field, or whose field nothing can fill: a contract, a form, a lease. The
person composes a signature once (typed in a script font, or drawn with a pen), then places it on each page that asks
for it. It looks written by hand, and it is part of the saved copy.

It is not a digital signature: nothing proves who signed. It is the picture of a signature, as on paper.

## Decisions

- One tool, Signature (S, the toolbar's group of marks). Turned on, it opens the dialog with the signature kept
  from last time. "Place" closes the dialog and keeps the tool on: the signature follows the pointer over the pages,
  and a click puts it there, centred on the click. The tool stays on for the next page (initials on every page);
  Escape leaves it. The style bar has "Change the signature…" and the ink's colours.
- Two ways, two tabs of the dialog:
  - **Typed**: the name in one of five script fonts (each row of the list shows the name in its font), with the
    effects of a pen: a tilt, a heavier pen, a flourish under it. It is one stamp of gt:pdf with its `face`, so it
    moves, turns and restyles as one mark, and its text stays copyable in the file.
  - **Drawn**: the person draws in a pad with the pointer. gt:ink turns each stroke into ink: its width follows the
    speed (fast is thin, slow is thick), its ends taper. The nibs are a ballpoint, a fountain pen (a broad nib: thin
    along its angle, thick across), a felt pen and a brush, with a thickness. The ink is one Outline shape of gt:pdf:
    filled contours, the width drawn as the pen made it, not a stroke of one width.
- Each nib has its ink, as gt:ink's presets describe it (`Pen.ink`), with no setting of its own: the person
  chooses a pen, not a list of effects.
  - Ballpoint: an opaque line that a starved ball thins to faint, scratches on one edge and rarely breaks, more where
    the hand is fast, on upstrokes and in a stroke's first millimetres; never in a pattern that repeats.
  - Fountain pen: translucent ink, so crossings darken; ink pooled where the nib lands and lifts; darker where the
    hand slows.
  - Felt pen: translucent, crossings darker, the paper's grain in its edges and streaks along its path.
  - Brush: the same, stronger, with pooling.
  - A stylus's pressure, where the system gives it, widens and darkens the line; its lean lays the side of a felt's
    or a brush's tip and turns a fountain pen's nib with the hand. Both are kept with the strokes' samples.
- The pad shows the finished strokes as the engine renders them (the preview thread), and draws the stroke under
  way itself as a plain outline: gt:draw's polygon fill, made for an interface's shapes, cannot draw a grained ink's
  hundreds of pieces (its edges between them showed, and it keeps 4096 points a fill). The picture is stale after any
  change but a new stroke (a pen, a colour, a stroke removed): the pad's epoch says which picture still holds.
- A translucent ink is composed on sRGB values by the engine and in linear light by the interface: the picture's
  alpha is chosen so the interface shows the engine's darkness, not the same alpha.
- The ink is drawn as levels: gt:ink lays a stroke as pieces of ink of varying density; the pieces are grouped in a
  few levels, and each level is one fill of the ink's colour at that level's alpha (multiplied, in the PDF). A
  stroke is its own fills, so where two strokes cross, two layers of ink darken it, as on paper. The pad draws the
  same levels: what the pad shows is what is placed.
- The mention and the caption are in the signature's language, not the program's: a document is signed in its own
  language. Seven languages, each with its usual turns, not a word-for-word translation ("Fait à Lyon, le …",
  "Lyon, den …", "Opgemaakt te Lyon op …") and its way of writing a date; the words are data of the signature
  (`SIGN_WORDS`), not texts of the interface's catalogue. A new signature takes the program's language when it is
  one of them, else English; another one added takes the language of the one before. The language dropdown sits on
  the ink-and-size bar with no separate label (its own name, "Français" or "English", already says what it is), right
  above the switches it governs.
- The values of a signature, each optional: "Read and approved" above it (in the script font: it is written by hand
  in France), and a line under it with the place and the date ("Done at Paris, on 19 November 2026"). The date is a
  calendar value (`Sign_Date`: year, month, day; today at each start, not kept), edited with `ui.parts_field` and
  its three drums (month names when the language writes them in words, numbers otherwise, the day bounded by the
  month's length): changing the language formats the chosen date in the new language at once. The place is kept.
- The colours are an ink's: black, blue, a dark blue. The size is one slider for both ways (a typed name's size, a
  drawing's width).
- What the dialog shows under the tabs is the signature as it goes on the page: the engine renders it (the preview
  thread, below), so the preview is the saved result, tilt, flourish and caption included. The font list and the
  pad are drawn by the interface at once, so typing and drawing never wait.
- The person keeps several signatures: their own, their initials, a colleague's mandate, a drawn one and a typed
  one. The dialog's top row lists them (a typed one shows its name in its hand, a drawn one its number); a click
  chooses the one the dialog edits and places, "+" adds a new one, the bin removes the chosen one (never the last).
  There is no "save": the chosen signature is the one being edited, and every change is kept.
- The signatures are kept in `signatures.txt` of the state folder (gt:store: read at the start, written by its
  worker): for each, the way, the name, the font, the effects, the colour, the size, the place, the pen, and the
  drawn strokes (their samples, so a change of pen redraws them with the new nib); and which one is chosen. The
  library is written when the dialog ends, when one is added, removed or imported, and when the program ends: not
  at each move of a slider.
- Export writes all of them to a `.signatures` file the person chooses; import adds the signatures of such a file
  to the list (one identical to a kept one is not added twice), and chooses the first added. It carries them to
  another computer, or shares a scanned colleague's drawn signature. The file is text: a first line
  `feuille signatures 1`, then the store's lines (`<n>.<field>`, a tab, the value). Reading and writing it is a task
  of the program's pool: the interface's thread touches no file.
- A placed signature is ordinary marks: a drag moves the part taken, Delete removes it, Undo takes the whole
  signature back. Its parts are placed in one edit (`Sign`), so one Undo removes all of it. A typed signature is one
  part; a drawn one is up to three (the mention, the ink, the caption), each movable alone.

## The preview thread

A thread of its own (a pool of one), not the document's worker: a preview never waits behind the pages' renders, and
the document never waits for a preview. It has two jobs:

- At the start, it gives the engine the five fonts (`pdf.font_add`) and posts their ids: an engine call never runs on
  the interface's thread. The tool waits for them (a few milliseconds).
- For each change of the signature, the newest ask only: it composes the marks (where the mention, the name or the
  ink, and the caption go, measured by the engine), renders them on a white page, and posts the marks, their size in
  points and the picture. The interface keeps the newest answer. Placing sends those marks to the worker, so what is
  placed is what was shown.

## Refused alternatives

- A digital signature (PAdES, a certificate): another feature, with keys and trust; this one is the visible mark.
- A signature as an image (PNG) in the page: it blurs when zoomed and prints badly; the font is vectors, and the
  drawn ink is a filled path.
- The drawn strokes as lines of one width (the Pen tool's): they look like a plotter, not a hand. A signature's
  character is the width that changes.
- A light line where a stroke crosses its own ink (feuille 0.8): the pad's fill antialiased along edges inside the
  ink. Fixed in gt:draw (only the edges between ink and paper are smoothed), not hidden here.
- Ink effects as switches (grain on, pooling on): a list of effects to tune is a design tool, not a pen. The nib
  carries them.
- One random draw a render: the seed of each stroke is kept with it, so a signature looks the same every time.
- Shaping the script fonts (ligatures, contextual forms): the fonts chosen join their letters without it.
- Each part as a separate placement: the person would place three things for one signature.
- A "Save" button and unsaved edits: one more state the person must think about, and a signature lost by a
  forgotten click. The chosen signature is always the kept one.
- Export as JSON or as a picture: the store's text needs no new reader, and a picture could not be placed as ink nor
  redrawn with another pen.
- Keeping the 0.7.0 file (`signature.txt`, one signature) readable: it lived one hour before this change.

## Subtle points

- The mention and the name are two lines of one stamp in the typed way; in the drawn way the mention is a script
  stamp above the ink and the caption a Helvetica stamp under it. Both ways give the same parts in the same order.
- A drawn signature is placed at its ink's box, not the pad's: the margins of the pad do not move it off the click.
- Fonts are given to the engine once per process (it keeps them): the dialog opened many times adds nothing.
