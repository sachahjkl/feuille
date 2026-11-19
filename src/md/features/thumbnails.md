# Thumbnails in the file managers

## Purpose

A folder of PDFs shown as their first pages, in Windows Explorer and in the Linux file managers, without another
program installed for it: Feuille gives them.

## Decisions

- The picture is the first page as Feuille opens it: the form layer hidden, fitted in the square the file manager asks
  (`src/thumbnail`, one procedure for both systems). A protected PDF gives none: there is no password to ask there.
- Linux: the freedesktop thumbnailer. The install writes a `.thumbnailer` file that runs `feuille --thumbnail %i %o %s`:
  no window, no single instance, no settings read; many may run at once.
- Windows: Explorer loads thumbnail providers only from an in-process COM DLL (`IThumbnailProvider`). That DLL is
  Feuille's own (`src/thumbnailer`, the toolkit's COM server `gt:shell_thumbnail` and the same engine), built with
  the program and embedded in `feuille.exe`; the install writes it beside the installed program and registers it for
  the user (HKCU). Nothing ships beside the program, and nothing of another vendor runs.
- A box of the install: "PDF thumbnails in the file managers", on by default. An uninstall takes it away.

## Refused alternatives

- A third-party provider (a PDF reader's, a shell extension pack): another program to install and trust.
- `feuille.exe` as the provider: Explorer loads no executable for this; a COM local server is not offered for
  thumbnails.
- The document's embedded thumbnail (`/Thumb`): few PDFs have one, and it may show what the layer hides.
