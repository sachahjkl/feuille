# feuille: intent

feuille opens a PDF at once, without the interactive layer that blocks other readers (signatures, annotations, form
fields). It arranges the pages (turn, add, remove, reorder), puts text on them, and saves a copy. This folder follows <https://srcmd.org>: it records why the code has its shape. The plan is
[ROADMAP.md](../../ROADMAP.md); the developer's how-to is [docs/development.md](../../docs/development.md).

## Overview

- Odin on gui_toolkit (collection `gt`), for Windows and Linux.
- The toolkit's `gt:pdf` (hayro, built in) reads, renders and writes; the document is a list of pages over files
  that never change (infrastructure/engine.md).
- Two sides, one direction each:
  - The document worker owns the list of pages and its sources. It loads, renders, edits and saves. Nothing else calls
    the engine.
  - The interface's thread owns a snapshot of the document (the page list) and the pictures. It sends asks; the worker
    posts answers (`ui.post`).
- The snapshot is what a frame reads: the page list with each page's size, rotation and identity, and a revision. Every
  edit makes a new snapshot. The layout of the column is computed from it once, not in each frame.
- The render draws the page's own content unless the person asks for the layer: no annotation is drawn, and the
  engine has no form environment. That is the masked opening, by construction.

## State machines

- The document: empty → loading → open, or → locked (a password is asked) → loading again, or → failed. Opening another
  file starts again from loading; the open document stays until the new one is open.
- A page's picture: absent → asked → ready. A new snapshot or a new zoom makes a ready picture stale: it stays on screen
  until its replacement comes.
- The interactive layer: hidden (default) or shown. A change asks for new pictures; it never reloads the file.
- An ask to the worker: the newest of each kind wins (a render ask replaces the waiting one; an edit never does).
- Saving: idle → saving → idle; the result (written, or why not) is posted.
- The start: a second start → forwarded (it ends); else the first → the last document reopened (`reopening`: its
  failure is not said) or the file given, or empty. The end: the instance let go → the install's thread ended → the
  installed copy or the restarted program started.
- The desktop's switches (`general.menu`, `general.autostart`): hidden → shown once a task found this copy is the
  integrated one.

## Subtleties

- One worker thread holds the list: the order of the asks is the order of the edits, with no lock on the list.
- A page keeps its identity through reorders and inserts: the cache keys on it, so a move re-renders nothing.
- A page's turns and stamps are part of its value: the render and the save read the same list, so what is shown is
  what is saved.
- The marking tools: none → one on (Text, a shape, the Highlighter). With one on, a press: on a mark → selected,
  then dragged (moved on release) or clicked (a text's field opens); elsewhere → a shape drawn while dragging (made on
  release) or, for Text, a new field. A text's field: open → committed or given up.
- The tests make their PDFs with a small writer (`src/fixture`): no binary file in the repository.

## File Index

- [data/snapshot.md](data/snapshot.md): the page list the interface reads, page identities, revisions, the layout
- [features/viewer.md](features/viewer.md): the column of pages, zoom, the visible pages, the picture cache
- [features/window.md](features/window.md): the toolkit's settings, palette, theme, licence and updates around the
  document; the program's commands, the window's buttons, the context menus; the README's pictures
- [features/desktop.md](features/desktop.md): the install, the single instance, the menu and the session switches,
  what waits on the system
- [features/memory.md](features/memory.md): the recent PDFs, each one's page and zoom, the last one at the start
- [features/masked-opening.md](features/masked-opening.md): why the layer is hidden, the password, the copy without
  security, the day-one test
- [features/page-edits.md](features/page-edits.md): the document as a list of pages; turn, add, remove, reorder,
  undo, the saved copy
- [features/thumbnails.md](features/thumbnails.md): the PDFs' first pages in Explorer and the Linux file managers,
  why Feuille's own DLL on Windows, why it is embedded
- [features/marks.md](features/marks.md): text and shapes put on a page, the tools, moving and restyling a mark,
  where it goes, why not the document's own words nor annotations
- [infrastructure/engine.md](infrastructure/engine.md): gt:pdf, why PDFium went (hayro measured against it), the
  worker, the fixtures
