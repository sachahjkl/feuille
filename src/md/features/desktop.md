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
- **One box: the PATH.** "Open PDF files with Feuille" (the default application of `application/pdf`) waits for the
  toolkit's desktop integration to know a file association. Its index is reserved beside `SETUP_PATH`. A box that wrote
  nothing would say a thing that is false.
- **The menu and the session follow the integrated copy only** (`desktop_follow`). `general.menu` and
  `general.autostart` stay hidden until a task finds that the copy that runs is the installed one; then a change of
  either applies to that install, the PATH left as the install made it. A build or Nix's copy installs nothing because
  of a preference. The task runs on a pool of one thread (`desktop_pool`): the changes apply in their order, the last
  one wins.
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
