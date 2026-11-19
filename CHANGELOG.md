# Changelog

All notable changes to feuille are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the versions follow [semantic versioning](https://semver.org/).

## [0.6.0] - 2026-11-19 12:03

### Added
- **Move, restyle or remove a mark.** With a tool on, drag a text or a shape to move it; the mark you took is outlined, the style bar changes it at once, and Delete removes it (no longer the page under it).
- **Draw on a page.** Rectangles, ellipses to circle something, lines, arrows, the pen and the highlighter (R, E, L, A, P, H): drag on the page to draw; the colour, the width and the fill in the toolbar. The highlighter is translucent, and the words under it stay readable. Like the texts, the shapes become part of the page in the saved copy.

## [0.5.0] - 2026-11-19 10:23

### Added
- **PDF thumbnails in the file managers.** Windows Explorer and the Linux file managers show each PDF as its first page, the form layer hidden. The install sets it up (a box of its own, on by default): on Windows Feuille writes its own small provider beside the program, which it carries inside, so nothing else is installed.

## [0.4.0] - 2026-11-17 21:28

### Added
- **Put text on a page.** The Text tool (T): a click places a text where you want it, in sans, serif or mono, bold or italic, the size and colour you choose, on no background or on white, yellow or black to hide what is under it. A click opens it again; it turns, moves and goes with its page, and undoes like any edit.
- **Print.** Ctrl+P opens the system's print dialog, with the page range and the copies; the pages print as they are shown, the form layer hidden unless it is drawn.
- **Open PDF files with Feuille.** The install puts Feuille in the file managers' Open with, and can make it the application of PDF files (on Windows, the Default apps page opens at Feuille).
- **Screen readers**: the pages, the thumbnails, the tools and the status bar have their roles and names, and the Windows build speaks to screen readers.
- **THIRD-PARTY-NOTICES**: the release's archive and the Nix package list the licences of every work Feuille holds, PDFium's included.
- **Feuille remembers the documents**: each PDF opens again at the page and the zoom it showed, the last one opens at the start when no file is given (`general.reopen_last`), and each PDF opened goes to the desktop's recent files.
- **Pages and recent PDFs in the palette**: `@` goes to a page ("Page 3 of 12", or its number; Ctrl+G), `/` opens a recent PDF (Ctrl+Shift+O).
- **Context menus**: a right click on a page or a thumbnail selects it and opens its menu: turn, move, add a blank page, remove, save the page as a PDF, copy the path, show in folder, open with.
- **The document's file**: Open with another application, Show in folder and Copy the path (Ctrl+Shift+C).
- **The suite's commands**: New window (Ctrl+N), Minimize (Alt+F9), Maximize (Alt+F10), Full screen (F11), Install the update, Restart to update, About, Open the website, Report a problem, Release notes, Open settings folder, Copy the version, the next and previous theme, Compact rows, Animations, and larger, smaller or default text (Ctrl+Alt+=, Ctrl+Alt+-, Ctrl+Alt+0), in the palette and by their keys.
- **Updates by itself once installed**: the installed copy downloads the new version and puts it in place (`update.auto`), on Linux and Windows.
- **In the applications menu, start with the session**: the settings' General page shows these two switches once the copy that runs is the installed one, and they change that install.
- **One window per person**: `feuille file.pdf` while Feuille runs opens the file in that window and brings it to the front; a document with unsaved edits asks first.
- **Install Feuille for you**: `feuille --install`, `--uninstall`, `--status` and `--setup`, the Setup a downloaded copy offers on Windows, and the settings' Installation page. The install puts Feuille in the applications menu with its icons and on the PATH; in a Windows terminal, `feuille` gives these commands their output and exit code.

### Changed
- **The PDF engine is inside the program.** Feuille no longer needs a PDFium library beside it: one file, on every system, and pages render about three times faster. A saved copy keeps the outlines, the form and the metadata of the file opened; a removed page leaves the file for good.
- **A larger logo.** The leaf fills its square: in the taskbar, the dock and the menus it stands as large as its neighbours.
- **The window's own buttons**: Feuille's title bar ends with minimise, maximise or restore, and close, in place of its close button alone.

### Removed
- **Changing the words of a text block.** It worked only where the document's font held the new letters, and moved nothing around them; putting text on the page replaces it.

### Fixed
- **The window is Feuille's from its first frame**: the desktop groups it with its launcher and shows its icon.
- **The emoji font setting is read**: the file named in `appearance.text.emoji_font` draws the emoji from the next start.
- **The system's title bar is offered only where it exists**: the setting is hidden on a Wayland compositor that draws no title bars.
- **The file dialog setting is obeyed**: `general.file_dialog` chooses the system's dialog or the toolkit's again, and the dialogs remember their folder and size.

## [0.3.0] - 2026-11-17 19:28

### Added
- **Thumbnails.** Every page small beside the document (Ctrl+B): a click shows it, a drag moves it.
- **Change the words.** Double-click a text block: a field opens over it with its words; Enter changes them in the PDF. Feuille says when the font may lack a new letter.
- **Arrange the pages.** Turn a page (Ctrl+R), remove it (Delete), add a blank page or the pages of another PDF after it, move it (Alt+Up, Alt+Down, or drag its thumbnail), save it alone as a PDF (Ctrl+E). Every edit undoes and redoes (Ctrl+Z, Ctrl+Shift+Z); Ctrl+S saves a copy, and leaving unsaved edits asks first.

## [0.2.0] - 2026-11-17 17:40

### Added
- **Windows.** Feuille runs on Windows 10 and 11 (x64): unzip the archive and start feuille.exe. Each archive, Windows and Linux, carries PDFium beside the program: nothing else to install.

## [0.1.0] - 2026-11-17 11:02

### Added
- **The whole window.** Feuille's own warm theme in the machined finish, its title bar, light and dark; every setting in the window (Ctrl+,), from the look and the keys to the language (English, French); every command at Ctrl+K and the keys at F1; the page number in the status bar; a licence page; updates checked from the settings.
- **Open and read a PDF.** The pages in one column: scroll, zoom with Ctrl+wheel or the zoom buttons, fit to the window. Open with Ctrl+O, from the command line, or by dropping a file on the window.
- **Nothing on the page blocks it.** Signatures, annotations and form fields are hidden when a PDF opens, so nothing takes the page or asks for input; Ctrl+L shows them as a picture. A protected PDF asks for its password in the window.
- **feuille's mark.** An autumn maple leaf in flight: the program's icon, the README's picture and the project's image.

[0.6.0]: https://github.com/sachahjkl/feuille/releases/tag/v0.6.0
[0.5.0]: https://github.com/sachahjkl/feuille/releases/tag/v0.5.0
[0.4.0]: https://github.com/sachahjkl/feuille/releases/tag/v0.4.0
[0.3.0]: https://github.com/sachahjkl/feuille/releases/tag/v0.3.0
[0.2.0]: https://github.com/sachahjkl/feuille/releases/tag/v0.2.0
[0.1.0]: https://github.com/sachahjkl/feuille/releases/tag/v0.1.0
