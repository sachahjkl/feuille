# Using feuille

## Open a PDF

- `feuille file.pdf` from a terminal. A feuille that runs already opens it in its window: one window per person.
- From the file manager, once feuille is installed with Nix: Open with > Feuille. The install of the archive
  (`feuille --install`) puts feuille in the applications menu; it offers to open the PDF files once the toolkit knows a
  file association ([desktop.md](desktop.md)).
- In the window: **Open** (Ctrl+O), drop a PDF on the window, or a recent PDF (Ctrl+Shift+O, or `/` in the palette).
- With no file, feuille opens the last PDF again, at its page and its zoom (`general.reopen_last`).

The document opens with its signatures, annotations and form fields hidden: only the pages' own content is drawn, and
nothing on the page takes the keyboard or asks for input. A protected PDF asks for its password in the window.

## Read

| Key or action | What it does |
|---|---|
| Wheel, scroll bar | moves through the pages |
| Page Up, Page Down, Ctrl+Home, Ctrl+End | the previous, next, first, last page |
| A thumbnail | shows that page (Ctrl+B shows or hides the thumbnails) |
| Ctrl+wheel over the pages, the zoom buttons | zoom the pages; ↔ fits the widest page to the window again |
| Ctrl+G | goes to a page (`@` in the palette, then its number) |
| Ctrl+L | shows or hides the signatures, annotations and form fields, as a picture |
| Ctrl+K | every command and setting; F1 lists the keys |
| F11, Alt+F9, Alt+F10 | full screen, minimise, maximise |
| Ctrl+N | a new window |

Each PDF keeps its zoom and its page: open it again and it is as you left it.

## Arrange the pages

The edits act on the selected page: click a page or its thumbnail to select it. A right click on a page or a thumbnail
selects it and opens its menu: the edits below, Copy the path (Ctrl+Shift+C), Show in folder, Open with.

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

## Put text on a page

Press T (or the toolbar's T), then click where the text goes: a field opens there. Type, then Enter; Escape gives up.
The toolbar shows the style while the tool is on: the family (sans, serif, mono), bold, italic, the size, the colour of
the words and of their background (none, white, yellow, black). A click on a text already put opens it again; empty
it to remove it. Each text turns, moves and goes with its page, and Ctrl+Z undoes it.

- The fonts are PDF's own (Helvetica, Times, Courier): every reader shows them, nothing is embedded.
- They hold the characters of Western European languages; another character is written as "?".
- The text goes on top of the page: a background hides what is under it. The document's own words do not change.

## Draw on a page

The toolbar's drawing tools, or their keys: Rectangle (R), Ellipse (E: to circle something), Line (L), Arrow (A),
Pen (P: freehand), Highlighter (H). Drag on the page to draw. The style bar shows the line's colour, its width and, for
a rectangle or an ellipse, the fill; the highlighter's colours are translucent, and the words under them stay
readable.

## Move, change or remove a mark

With any of these tools on (text included), press on a text or a shape and drag it: it moves. A click on a text opens
it. The mark you took is outlined: the style bar changes it at once, and Delete removes it (the page stays). Escape
lets it go, then leaves the tool. Every mark undoes and redoes, and goes with its page when the page turns or moves.
