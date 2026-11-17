# Masked opening

## Purpose

The person opens an administrative PDF to read it. In Acrobat and other readers it blocks: a form field, a signature
widget or an annotation takes the page, asks for input, or holds the view. feuille draws the page's own content and
nothing else, so nothing can block.

## Decisions

- The render passes no annotation flag: PDFium draws no annotation, no form widget, no signature appearance. The file is
  not changed; the layer is only not drawn.
- No form environment (`FPDFDoc_InitFormFillEnvironment`) is ever made: no field focus, no validation, no form
  JavaScript. Nothing interactive exists in the process.
- A toggle shows the layer (the appearances, drawn as pictures, still not interactive). It asks for new pictures only.
- A protected file: the load fails with the password error; the window shows a password field over the empty view, the
  worker loads again with it. A wrong password says so and keeps the field. Cancel returns to the state before.
- A saved copy drops the encryption and the restrictions (`FPDF_REMOVE_SECURITY`).

## Refused alternatives

- Flattening at open (`FPDFPage_Flatten`): it bakes the layer into the page, the opposite of hiding it, and it breaks
  the signatures.
- Removing the annotations at open: it changes the document before the person asks anything. The mask is a view, not an
  edit.

## The day-one test

The test's writer makes one page: a blue base rectangle, a text field with a red appearance, a signature widget with a
green appearance, a text annotation, all encrypted with a user password. The test checks, in order: the load without
the password gives the password error; the load with it opens one page; the render without the flag has the blue and
none of the red or green; the render with the flag has the red and the green; the copy saved without security opens
with no password and keeps the blue.
