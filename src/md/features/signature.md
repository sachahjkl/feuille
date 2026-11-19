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
- The values of a signature, each optional: "Read and approved" above it (in the script font: it is written by hand
  in France), and a line under it with the place and the date ("Done at Paris, on 19/11/2026"). The date is today
  at each opening, and the field can change it. The place is kept.
- The colours are an ink's: black, blue, a dark blue. The size is one slider for both ways (a typed name's size, a
  drawing's width).
- What the dialog shows under the tabs is the signature as it goes on the page: the engine renders it (the preview
  thread, below), so the preview is the saved result, tilt, flourish and caption included. The font list and the
  pad are drawn by the interface at once, so typing and drawing never wait.
- The signature is kept in `signature.txt` of the state folder (gt:store: read at the start, written by its worker):
  the way, the name, the font, the effects, the colour, the size, the place, the pen, and the drawn strokes (their
  samples, so a change of pen redraws them with the new nib).
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
- Shaping the script fonts (ligatures, contextual forms): the fonts chosen join their letters without it.
- Each part as a separate placement: the person would place three things for one signature.

## Subtle points

- The mention and the name are two lines of one stamp in the typed way; in the drawn way the mention is a script
  stamp above the ink and the caption a Helvetica stamp under it. Both ways give the same parts in the same order.
- A drawn signature is placed at its ink's box, not the pad's: the margins of the pad do not move it off the click.
- Fonts are given to the engine once per process (it keeps them): the dialog opened many times adds nothing.
