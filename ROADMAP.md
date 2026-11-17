# Roadmap

## Now

- **Page edits.** Turn, add (blank or from another PDF), remove and reorder pages, undo, save a copy.
  [Page edits](src/md/features/page-edits.md).

## Next

- **A test bench of engines.** Hard real PDFs (forms, signatures, encrypted, damaged) rendered by PDFium and by hayro,
  a renderer in pure Rust, their pictures and failures compared; hayro becomes a backend of the toolkit if it holds.

- **Text editing.** Change the words of a text block in the PDFs whose fonts allow it.
  [Text editing](src/md/features/text-editing.md).
- **Thumbnails.** A strip of the pages beside the document, to move through it and drag pages into a new order.
- **French.** The interface in French, from the toolkit's catalogues.
- **The live test and the pictures.** The real program in a sway nobody sees; the README's pictures.

## Later

- **Text selection and search.** Select, copy and find the text of a page.
- **Print.** The system's print dialog, the pages rendered at the printer's resolution.
- **Extract.** Save the chosen pages as a new PDF.
- **The engine in the toolkit.** `gt:pdf` when a second program (classeur's preview) needs it.
