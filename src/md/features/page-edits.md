# Page edits

## Purpose

Arrange the pages: turn a page scanned sideways, add a blank page or the pages of another PDF, remove a page, change
the order. Then save a copy.

## Decisions

- Turn: the page's `/Rotate` (`FPDFPage_SetRotation`). The render reads the same attribute.
- Add: a blank page (`FPDFPage_New`, the size of its neighbour) or pages of another PDF (`FPDF_ImportPagesByIndex`).
  The other PDF is opened on the worker, read, closed, never changed.
- Remove: `FPDFPage_Delete`. Reorder: `FPDF_MovePages`.
- Each edit is an operation with its inverse, kept on the worker's undo stack. Undo of a remove re-imports the page
  from a copy the worker kept in a scratch document at the remove. Undo of an add removes it. Undo of a move moves it
  back. Undo of a turn sets the old rotation.
- Save: `FPDF_SaveAsCopy` to the file the person chooses, `FPDF_REMOVE_SECURITY`. The save dialog proposes
  "<name> (edited).pdf" beside the original. Choosing the original's own path asks for a confirmation first. A failed
  save keeps the document and its edits.

## Refused alternatives

- Rebuilding the document by importing every page into a new one at save: it loses the bookmarks and the links.
- A list of edits replayed at save: two truths. The document is the truth; undo applies inverses.
