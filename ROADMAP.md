# Roadmap

## Now

- **Open and read.** A PDF opens at once and reads as a column of pages: scroll, zoom, keyboard.
  [The engine](src/md/infrastructure/pdfium.md).
- **The masked opening.** Signatures, annotations and form fields are not drawn, so nothing blocks the document; a
  toggle shows them; a protected file asks for its password. [Masked opening](src/md/features/masked-opening.md).

## Next

- **Page edits.** Turn, add (blank or from another PDF), remove and reorder pages, undo, save a copy.
  [Page edits](src/md/features/page-edits.md).
- **Text editing.** Change the words of a text block in the PDFs whose fonts allow it.
  [Text editing](src/md/features/text-editing.md).
- **Thumbnails.** A strip of the pages beside the document, to move through it and drag pages into a new order.
- **The live test and the pictures.** The real program in a sway nobody sees; the README's pictures.

## Later

- **Text selection and search.** Select, copy and find the text of a page.
- **Print.** The system's print dialog, the pages rendered at the printer's resolution.
- **Extract.** Save the chosen pages as a new PDF.
- **Windows.** The engine's loader for Windows, the console launcher and the installer.
- **The engine in the toolkit.** `gt:pdf` when a second program (classeur's preview) needs it.
