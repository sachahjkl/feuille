# feuille on the desktop

## Purpose

feuille is installed, started and found as its siblings (classeur, papier) are: one install for the person, one window
per person, a second start that hands its file to the first. A person who installed one knows how to install the
others. The how-to is [docs/desktop.md](../../../docs/desktop.md).

## Decisions

- **The toolkit's install, whole.** `gt:setup` through `prefs_page.Install`: `feuille --install`, `--uninstall`,
  `--status`, `--setup`, the dialog and the settings' Installation page. feuille gives its identity (`src/integration.odin`:
  its name, its icons, "PDF Reader", `Office;Viewer;Graphics;`) and its boxes. Windows offers the install at the start
  (`SETUP_AT_START`, `src/system_windows.odin`); Linux has Nix or `feuille --install`.
- **Three boxes: the PATH, Open with, the default.** "Open PDF files with Feuille" puts Feuille in the file managers'
  Open with (the toolkit's `Documents` part: `.pdf`, `application/pdf`); "Feuille opens PDF files by default" makes it
  the PDF files' application on Linux, and opens Windows' Default apps page at Feuille, since Windows lets only the
  person choose. The PDF type is always named, box ticked or not: an uninstall reads it to take it away.
- **The menu and the session follow the installed copy only**, by the toolkit (`prefs_page.install_follow`):
  `general.menu` and `general.autostart` stay hidden until the install's reading finds that the copy that runs is the
  installed one; then a change of either applies to that install, its other parts left as the install made them. A
  build or Nix's copy installs nothing because of a preference. feuille has no code of its own for them.
- **One window per person** (`gt:instance`, its server on a thread of its own). A second `feuille file.pdf` sends its
  file, its launcher's activation token and `--setup` when given; the first opens the file as a drop does (an edited
  document asks first), raises its window with the token (Wayland's focus rule) and ends nothing. `--status` pings it;
  an installer's quit asks as Quit does. A debug build has its own name: a build tried beside the installed copy does
  not hand its files to it.
- **New window** starts another feuille with no file. It owns no instance (the first one has it), so it is a window of
  its own; a later start still goes to the first.
- **The end's order.** The instance is let go before the window closes its state, then the install's thread ends, then
  the installed copy (an install's Launch) or the new program (an update, Restart) starts: each one that starts finds
  the name free and owns it.

## Subtleties

- The executable's path is read once at the start (`app.exe`): after an update the file is the new program, and a
  restart reads nothing on the interface's thread.
- Everything that waits on the system is a task (`src/launch.odin`): the browser, the file manager, Open with and its
  list of applications, the desktop's recent files, a new feuille. Headless (the tests), nothing starts: what would have
  is noted in `app.opened`.
- The tests never reach the instance: `run` owns it, and the tests call `app_open` headless.
