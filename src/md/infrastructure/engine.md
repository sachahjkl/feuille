# The PDF engine

## Choice

`gt:pdf`, the toolkit's engine: hayro (pure Rust) reads and renders, a writer of the toolkit's makes the files. It is
built into the program (`toolbox.Feature.Pdf`): nothing ships beside feuille, on any system. Its design is the
toolkit's (`ext/gui_toolkit/src/md/features/pdf.md`): a document is the program's list of pages over files that never
change.

Refused:

- PDFium (feuille 0.1 to 0.3): a 6 MB library beside the program, global state fenced on one thread, traps found by
  tests (byte order, fill), C memory safety; and its in-place edits made the engine the document's truth.
- MuPDF (AGPL), Poppler (GPL and a heavy chain of dependencies), a renderer of our own.

### hayro, measured against PDFium

Before the change, `feuilletool bench` (commit c98bd26, since removed) rendered 37 hard files of pdf.js's test suite
and feuille's fixtures with both:

- hayro opened 36 of 37; it refused an AES-256 file whose encryption covers only its attachments. No page failed, no
  panic.
- Its pictures equal PDFium's to the eye; the measured gap (up to 8 % of pixels on dense text) is anti-aliasing.
- 2.8 times faster: 369 ms against 1023 ms.

The edits PDFium made (turn, remove, import, move, save) are list operations plus the toolkit's writer; the one edit
hayro's model cannot make, changing a document's own words, gave way to stamps (features/marks.md).

## The worker

One `gt:tasks` pool of one thread holds the document (`src/worker.odin`): the list of pages, the sources it reads
from, the undo and redo stacks. The engine itself may be called from any thread; one worker keeps the order of the
asks (an edit, then the render of its result) without a lock on the list.

The asks (open, render, edit, save) wait in a mailbox under a lock. One `tasks.Job` serves them: asked while waiting,
nothing more; asked while running, one more run. The worker takes the whole mailbox at the start of a run, in order:
open first (it makes the rest moot), then edits, then saves, then renders. A render ask replaces the waiting one.

## The fixtures

The tests' writer (`src/fixture`) writes the objects, the streams, the cross-reference table, and the standard
security handler's RC4 40-bit encryption. The engine's API makes no encrypted file and no widget's appearance, so the
writer does; the fixture is exactly what the test claims, and no binary file enters the repository.
