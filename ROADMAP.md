# Roadmap

## Now

- **A test bench of engines.** Hard real PDFs (forms, signatures, encrypted, damaged) rendered by PDFium and by hayro,
  a renderer in pure Rust, their pictures and failures compared; hayro becomes a backend of the toolkit if it holds.

## Next

- **Several pages at once.** Select several pages (Ctrl and Shift clicks) to turn, remove, move or extract them
  together.
- **Text selection and search.** Select, copy and find the text of a page.
- **The live test.** The real program in a sway nobody sees, driven over the DevTools protocol.

## Later

- **Print.** The system's print dialog, the pages rendered at the printer's resolution.
- **The engine in the toolkit.** `gt:pdf` when a second program (classeur's preview) needs it.
