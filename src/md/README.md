# feuille: intent

feuille opens a PDF at once, without the interactive layer that blocks other readers (signatures, annotations, form
fields). It arranges the pages (turn, add, remove, reorder), edits the words of the documents that allow it, and saves a
copy. This folder follows <https://srcmd.org>: it records why the code has its shape. The plan is
[ROADMAP.md](../../ROADMAP.md); the developer's how-to is [docs/development.md](../../docs/development.md).

## Overview

- Odin on gui_toolkit (collection `gt`). Linux first; Windows later, through the toolkit.
- PDFium does the PDF work, through a thin binding opened with dlopen (`src/pdf`).
- Two sides, one direction each:
  - The document worker owns the engine and the open document. It loads, renders, edits and saves. Nothing else calls
    the engine.
  - The interface's thread owns a snapshot of the document (the page list) and the pictures. It sends asks; the worker
    posts answers (`ui.post`).
- The snapshot is what a frame reads: the page list with each page's size, rotation and identity, and a revision. Every
  edit makes a new snapshot. The layout of the column is computed from it once, not in each frame.
- The render never sets the annotation flag unless the person asks: the interactive layer is not drawn, and no form
  environment exists. That is the masked opening, by construction.

## State machines

- The document: empty → loading → open, or → locked (a password is asked) → loading again, or → failed. Opening another
  file starts again from loading; the open document stays until the new one is open.
- A page's picture: absent → asked → ready. A new snapshot or a new zoom makes a ready picture stale: it stays on screen
  until its replacement comes.
- The interactive layer: hidden (default) or shown. A change asks for new pictures; it never reloads the file.
- An ask to the worker: the newest of each kind wins (a render ask replaces the waiting one; an edit never does).
- Saving: idle → saving → idle; the result (written, or why not) is posted.

## Subtleties

- PDFium is not thread-safe: one worker thread makes every engine call. The binding checks it in debug builds.
- A page keeps its identity through reorders and inserts: the cache keys on it, so a move re-renders nothing.
- Rotation is the page's own `/Rotate`: what is shown is what is saved.
- The tests make their PDFs with a small writer (`src/pdf/fixture_test.odin`): no binary file in the repository.

## File Index

- [data/snapshot.md](data/snapshot.md): the page list the interface reads, page identities, revisions, the layout
- [features/viewer.md](features/viewer.md): the column of pages, zoom, the visible pages, the picture cache
- [features/masked-opening.md](features/masked-opening.md): why the layer is hidden, the password, the copy without
  security, the day-one test
- [features/page-edits.md](features/page-edits.md): turn, add, remove, reorder, undo, the saved copy
- [features/text-editing.md](features/text-editing.md): what "supported" means, the edit, its limits
- [infrastructure/pdfium.md](infrastructure/pdfium.md): the engine choice, the refused alternatives, the binding, the
  worker
