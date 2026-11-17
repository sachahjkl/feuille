# Feuille on the desktop

## Windows

Unzip the archive and start `feuille.exe`: its Setup offers to install it for you. Install copies it to
`%LOCALAPPDATA%\Programs\feuille` and writes a launcher in the Start menu, `feuille` on your PATH and the Settings >
Apps entry. The same dialog repairs, upgrades (start the newer `feuille.exe`) or removes the install: `feuille --setup`,
Settings > Apps > Feuille > Uninstall, or Feuille's own settings, page Installation, which also says where everything
is. Keep standalone runs the copy where it is, and the Setup does not ask again.

With the PATH comes `feuille.com` beside `feuille.exe`: in cmd or PowerShell `feuille` runs `feuille.com`, which gives
the install's commands their output and their exit code, and gives the prompt back at once for `feuille file.pdf`.

## Linux

`feuille --install` installs the downloaded program for you: the program in `~/.local/share/feuille`, and

- a launcher in the applications menu, with its icons;
- a link `~/.local/bin/feuille`, so that `feuille` works in a terminal.

```sh
tar -xzf feuille-0.3.0-linux-x64.tar.gz
./feuille-0.3.0-linux-x64/feuille --install      # or --setup: the dialog, which says what is there
feuille --status                                 # what is there, and whether feuille runs
feuille --uninstall                              # takes it all away; the settings stay
```

Feuille needs Vulkan (any driver, Mesa included), fontconfig and libxkbcommon.

## The settings of an install

Once the copy that runs is the installed one, the settings' General page shows two switches: In the applications menu
(`general.menu`) and Start with the session (`general.autostart`). They act on that install only: a copy that is not
installed (a build, Nix's) installs nothing because of a setting. The installed copy updates by itself
(`update.auto`).

## Open PDF files with Feuille

Nix's package declares the PDF type: the file managers list Feuille under Open with, and the system's default
application can be set to it. The install of the archive does not yet: it waits for gui_toolkit's desktop integration
to know a file association, then the install's dialog offers a box for it.

## One window

One Feuille runs per person. `feuille file.pdf` while one runs opens the file in that window, which comes to the front;
a document with unsaved edits asks first. New window (Ctrl+N) starts another Feuille of its own.

## NixOS and home-manager

The flake builds Feuille from source:

```nix
# flake.nix of your system
inputs.feuille.url = "github:sachahjkl/feuille";

# configuration.nix, or home.nix with home.packages
environment.systemPackages = [ inputs.feuille.packages.x86_64-linux.default ];
```
