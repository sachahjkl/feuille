# The PDF engine

## Choice

PDFium, Chromium's PDF engine: a C API (`fpdfview.h` and its companions), BSD, about 6 MB. It renders, edits pages,
imports, saves and reads text. The flake pins the prebuilt library of bblanchon/pdfium-binaries (chromium/8152).

Refused:

- MuPDF: AGPL, which would bind the whole program.
- Poppler: GPL, and a heavy chain of dependencies (GLib or Qt).
- A PDF renderer of our own: years of work.

## The binding

`src/pdf`: the C declarations feuille uses, loaded at run time (`load_linux.odin`: dlopen; `load_windows.odin`:
LoadLibraryW), as gt:ocr loads Tesseract. A program that never opens a PDF starts without the library, and `pdf.init`
says it is missing.

The library goes beside the program: a release's archive carries `libpdfium.so` or `pdfium.dll`, and the loader looks
in the program's own folder first (Windows does so by itself; Linux reads /proc/self/exe), then on the system's path.
`feuilletool` puts it in `build/` before each build and test (its `prepare`): from `$PDFIUM_LIB` (the flake's, as Nix's
sandbox has no network), else the pinned archive of pdfium-binaries checked by its SHA-256. Refused: linking it at build
time (a program that could not start without it), and asking each person to install it (no distribution packages it). The binding is thin: the C handles
as distinct types, no wrapper objects.

Facts of the pinned engine that shaped the binding (each found by a test):

- `FPDF_REVERSE_BYTE_ORDER` and `FPDFBitmap_FillRect` stop the process (a trap in the AGG renderer). `render` fills
  the paper itself, renders BGRx, then swaps the bytes to RGBA.
- `FPDF_LoadMemDocument64` reads the bytes for as long as the document is open: `Document` owns them.
- `FPDF_RenderPageBitmap` never draws form widgets; `FPDF_FFLDraw` does (masked-opening.md).

## The worker

One `gt:tasks` pool of one thread owns the engine (`src/worker.odin`). PDFium has global state and is not thread-safe:
every call, `init` included, runs there. In debug builds the binding records that thread at `init` and stops on a call
from another.

The asks (open, render, edit, save) wait in a mailbox under a lock. One `tasks.Job` serves them: asked while waiting,
nothing more; asked while running, one more run. The worker takes the whole mailbox at the start of a run, in order:
open first (it makes the rest moot), then edits, then saves, then renders. A render ask replaces the waiting one.

## The fixtures

The tests' writer (`src/fixture`) writes the objects, the streams, the cross-reference table, and the
standard security handler's RC4 40-bit encryption. The public API cannot make an encrypted file or a widget's
appearance, so the writer does; the fixture is exactly what the test claims, and no binary file enters the repository.
