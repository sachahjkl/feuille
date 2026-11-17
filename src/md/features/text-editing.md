# Text editing

## Purpose

In the PDFs that allow it, the person changes the words of a text block in place: double-click, type, Enter.

## What "supported" means

A PDF's text is runs of glyphs in text objects, each with a font. Three limits decide:

- The text is a text object (`FPDF_PAGEOBJ_TEXT`). Outlines and scans are not text: the program says there is nothing
  to edit there.
- The font has the new characters. An embedded subset font (a base name like `ABCDEF+Name`) has only the glyphs the
  document used. The program says so before the edit; the render shows the result.
- No reflow. The text stays in its object; a longer text runs past its box. feuille is not a word processor.

## Decisions

- Hit test on the worker: `FPDFText_LoadPage`, `FPDFText_GetCharIndexAtPos`, then `FPDFText_GetTextObject`.
  `FPDFTextObj_GetText` gives the text, the object's bounds place the field.
- The field is the window's own, over the block. Enter commits, Escape cancels.
- Commit: `FPDFText_SetText`, `FPDFPage_GenerateContent`, one undoable edit (the inverse sets the old text).

## Refused alternatives

- Reflow: a layout engine over a format that has none.
- OCR to make scans editable: another program's work.
- Export to another format and back: it loses the document.

## Subtleties

- A text object can hold several runs; `FPDFText_SetText` writes one. The object's inner splits are lost, its position
  and font stay.
