# Page edits

## Purpose

Arrange the pages: turn a page scanned sideways, add a blank page or the pages of another PDF, remove a page, change
the order, take one page out as its own PDF, put text on a page (stamps.md). Then save a copy.

## Decisions

- The document is a list of pages (gt:pdf's model, the toolkit's src/md/features/pdf.md): each a page of an open file
  (the file opened, or a file imported) or a blank page, with its quarter turns and its stamps. The files never change;
  an edit changes the list, on the worker (`src/edits.odin`).
- The edits act on the selected page: a click on a page or its thumbnail selects it. When it goes, the page after it is
  selected.
- Turn: the page's turns. The render and the save read the same list: what is shown is what is saved.
- Add: a blank page (the size of the page before it) or every page of another PDF, opened on the worker as a source that
  stays open while the document is (an undo or a redo may bring its pages back).
- Remove, move (Alt+Up and Alt+Down, a thumbnail dragged).
- Extract: the page written alone as a new file (`pdf.write` without a base); the document does not change.
- Each edit is an operation that, applied, gives its inverse. Undo applies the top inverse and keeps that one's inverse
  for redo; a new edit forgets the redo stack. A removed page's value goes into its inverse: the undo puts that very
  value back, with its turns and stamps. There is nothing to park anywhere: the page's content is its file's.
- Pages have identities (data/snapshot.md); an operation names its page by identity, the worker finds its index when it
  applies.
- "Edited" is a state, not a flag: each new edit makes a state number, the top of the undo stack is the state shown,
  the save remembers the state it wrote.
- Save: `pdf.write(pages, base = the file opened)` to the file chosen: the outlines, the form, the structure and the
  metadata of the file opened are kept, a removed page and what only it used leave the file, and the copy is not
  encrypted. The dialog proposes "<name> (edited).pdf" beside the original; choosing the original asks first. The saved
  file becomes the document's file. A failed save keeps the document and its edits, and says so.
- Leaving a document with edits not saved (another file, Quit, the window closed) asks first.

## Refused alternatives

- Editing the engine's objects in place (feuille 0.3's PDFium model): the engine held the truth, each edit needed an
  inverse in the engine, and a removed page waited in a scratch document.
- A list of edits replayed at save: two truths. The list is the truth; undo applies inverses.
