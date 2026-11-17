# Using feuille

## Open a PDF

- `feuille file.pdf` from a terminal, or open a PDF with feuille from the file manager.
- In the window: **Open** (Ctrl+O), or drop a PDF on the window.

The document opens with its signatures, annotations and form fields hidden: only the pages' own content is drawn, and
nothing on the page takes the keyboard or asks for input. A protected PDF asks for its password in the window.

## Read

| Key or action | What it does |
|---|---|
| Wheel, scroll bar | moves through the pages |
| Page Up, Page Down, Ctrl+Home, Ctrl+End | the previous, next, first, last page |
| A thumbnail | shows that page (Ctrl+B shows or hides the thumbnails) |
| Ctrl+wheel over the pages, the zoom buttons | zoom the pages; ↔ fits the widest page to the window again |
| Ctrl+L | shows or hides the signatures, annotations and form fields, as a picture |
| Ctrl+K | every command and setting; F1 lists the keys |

## Arrange the pages

The edits act on the selected page: click a page or its thumbnail to select it.

| Key or action | What it does |
|---|---|
| Ctrl+R, Ctrl+Shift+R | turns the page right, left |
| Delete | removes the page |
| Ctrl+Shift+N | adds a blank page after it, of its size |
| Ctrl+I | adds the pages of another PDF after it |
| Alt+Up, Alt+Down, a thumbnail dragged | moves the page |
| Ctrl+E | saves the page alone as a new PDF |
| Ctrl+Z, Ctrl+Shift+Z (Ctrl+Y) | undoes, redoes |
| Ctrl+S | saves a copy: by default beside the file, "<name> (edited).pdf"; the original is replaced only after a question |

A saved copy has no password and no restriction. Leaving a document with unsaved edits (another file, Quit, closing
the window) asks first.

## Change the words

Double-click a text block (or F2, then a click): a field opens over it with its words. Enter changes them, Escape gives
up; Ctrl+Z undoes the change. What can be changed:

- Text that is text in the PDF. A scanned page or letters drawn as shapes are pictures: there is nothing to edit.
- The letters its font has. Many PDFs embed only the letters they use: a new letter may not show; feuille says so when
  the field opens.
- No reflow: longer words run past the block; the lines around do not move.
