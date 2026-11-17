# Page edits

## Purpose

Arrange the pages: turn a page scanned sideways, add a blank page or the pages of another PDF, remove a page, change
the order, take one page out as its own PDF. Then save a copy.

## Decisions

- The edits act on the selected page: a click on a page or its thumbnail selects it. When it goes, the page after it is
  selected. No multiple selection yet: one page at a time covers the documents feuille is for.
- Turn: the page's `/Rotate` (`FPDFPage_SetRotation`). The render reads the same attribute: what is shown is what is
  saved.
- Add: a blank page (`FPDFPage_New`, the size of the page before it) or every page of another PDF
  (`FPDF_ImportPagesByIndex`). The other PDF is opened on the worker, read, closed, never changed.
- Remove: `FPDFPage_Delete`. Move: `FPDF_MovePages`, by Alt+Up and Alt+Down or a thumbnail dragged.
- Extract: the page imported into a new document of the engine, saved as its own file; the document does not change.
- Each edit is an operation that, applied, gives its inverse (`src/edits.odin`). Undo applies the top inverse and keeps
  that one's inverse for redo; a new edit forgets the redo stack. A removed page is first imported into a scratch
  document: its undo imports that very page back (its content, its annotations), not a copy made later. A blank page or
  an import is undone by removing what it added, which keeps those pages in the scratch for a redo.
- Pages have identities (data/snapshot.md); an operation names its page by identity, the worker finds its index when it
  applies. An undo after other edits still finds its page.
- "Edited" is a state, not a flag: each new edit makes a state number, the top of the undo stack is the state shown,
  the save remembers the state it wrote. Undoing back to the saved state is not edited.
- Save: `FPDF_SaveAsCopy` to the file chosen, `FPDF_REMOVE_SECURITY`; the dialog proposes "<name> (edited).pdf" beside
  the original. Choosing the original asks first. The saved file becomes the document's file. A failed save keeps the
  document and its edits, and says so.
- Leaving a document with edits not saved (another file, Quit, the window closed) asks first.

## Refused alternatives

- Rebuilding the document by importing every page into a new one at save: it loses the bookmarks and the links.
- A list of edits replayed at save: two truths. The document is the truth; undo applies inverses.
- Keeping the bytes of the whole document for each undo: memory in proportion to the document times the edits.
