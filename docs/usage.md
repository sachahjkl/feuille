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
| Page Up or ←, Page Down or →, Ctrl+Home, Ctrl+End | the previous, next, first, last page |
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

## Sign

Press S (or the toolbar's signature): the signature's dialog opens with the one you chose last time.

The row at its top holds your signatures: a typed one shows its name in its hand, a drawn one its number. Click one to
use it and change it; + adds a new one; the bin removes the one chosen (the last one stays). Every change is kept,
there is nothing to save. The two buttons beside them export all of them to a `.signatures` file, and import the
signatures of such a file (one you already have is not added again): take them to another computer, or keep a copy.

- **Type it**: your name, then the hand it is written in (five script fonts, each shown with your name), its slant,
  how hard the pen presses, and a flourish under it.
- **Draw it**: sign in the box with the pointer, or a stylus. The ink thins where you go fast and darkens where you
  slow down, as on paper, and its ends taper. Each nib has its own ink:
  - a ballpoint: a line that a dry ball now and then pales, scratches or breaks where the hand runs fast;
  - a fountain pen: thick across its nib and thin along it, translucent ink that pools where the nib lands and lifts;
  - a felt pen: the paper's grain in its edges and streaks along the stroke;
  - a brush: the same, stronger, with pools.

  Where two strokes cross, the ink is laid twice and darker. A stylus's pressure widens and darkens the line; leaned,
  a felt pen or a brush lays the side of its tip, broader and lighter, and a fountain pen's nib turns with your hand
  (Windows, Wayland and X11). The
  stroke under way is drawn at once; its ink settles when you lift the pen. The arrow takes the last stroke back;
  Clear starts again. A change of nib or thickness redraws what is there.
- Both: the ink's colour (black, blue, dark blue), the size, the language, "Read and approved" above it, and the
  place and the date under it ("Done at Lyon, on 21 November 2026"). The date is today's: type or step each part,
  or click it to spin its drums.
- The words are in the document's language, whatever Feuille's: French, English, German, Spanish, Italian,
  Portuguese or Dutch, each with its own turns ("Lu et approuvé", "Fait à Lyon, le 21/11/2026"; "Gelesen und
  genehmigt", "Lyon, den 21.11.2026") and its own way of writing the date. Each signature keeps its language.

The picture at the bottom is the signature as it goes on the page. "Place on the page" closes the dialog; the
signature follows the pointer over the pages, and a click puts it there, centred. Click on each page that asks for
it; Escape leaves. A placed signature is one mark, with its mention and its date: a drag on any part moves all of
it, Delete removes it, Ctrl+Z takes it back. The toolbar's pen opens the dialog again, and its colours recolour the
signature you chose.

A typed signature's font is embedded in the saved copy (only its letters), and its words stay copyable. It is the
picture of a signature, as on paper: it proves nothing about who signed.

## Move, change or remove a mark

With any of these tools on (text included), press on a text or a shape and drag it: it moves. A click on a text opens
it. The mark you took is outlined: the style bar changes it at once, and Delete removes it (the page stays). Escape
lets it go, then leaves the tool. Every mark undoes and redoes, and goes with its page when the page turns or moves.
