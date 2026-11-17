# Roadmap

## Now

- **Several pages at once.** Select several pages (Ctrl and Shift clicks) to turn, remove, move or extract them
  together.

## Next

- **Open PDF files with Feuille.** A box of the install makes Feuille the PDF files' application, and the file
  managers list it under Open with. It waits for gui_toolkit's desktop integration to know a file association
  (src/md/features/desktop.md).
- **The PDF engine in an install.** `feuille --install` copies the program alone: PDFium beside it in the archive stays
  behind. The toolkit's setup must take the files a program names beside it (its install plan has them, its options
  do not), or the engine must be inside the program.
- **Text selection and search.** Select, copy and find the text of a page.
- **The live test.** The real program in a sway nobody sees, driven over the DevTools protocol.

## Later

- **Print.** The system's print dialog, the pages rendered at the printer's resolution.
- **The engine in the toolkit.** `gt:pdf` when a second program (classeur's preview) needs it. A program that only
  shows PDFs can render with hayro, measured on par with PDFium and faster (src/md/infrastructure/pdfium.md).
