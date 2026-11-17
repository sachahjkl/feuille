# What feuille remembers of the documents

## Purpose

A PDF opened again comes back as it was left: at its page, at its zoom. The last one opens by itself when feuille
starts with no file. The recent ones are a key away (`/` in the palette, Ctrl+Shift+O).

## Decisions

- **Two small files of the state folder** (`gt:store`): `documents.txt` (a path, then the page it showed last; the most
  recent first) and `zooms.txt` (the toolkit's `Zoom_Memory`, keyed by the path, which is the pages' zoom zone's key).
  They are read once at the start, before the window shows, as the preferences are; after that a frame changes them in
  memory only and the stores' workers write them.
- **A bounded list.** `RECENT_KEPT` documents. One that leaves the list leaves its zoom too, and a file that is gone
  (an open fails with `.File`) leaves it at once: neither file grows without end.
- **The page is written when it changes**, not at each frame: `recent_page_keep` compares with the last page written.
- **The last document at the start** is `general.reopen_last` (on). Its failure is not said: the window starts empty,
  as with no last document, and a file that is gone leaves the list. A password asked is asked.
- **Jump, not scroll.** A document opened at its last page shows that page in its first frame (`go_jump`): a scroll
  from the top would show pages nobody asked for and render them.
- **The desktop's recent files** (`platform.add_recent_file`) get each document opened, on a task.

## Refused

- One file for both: the zoom memory owns its store (it writes through it), and the list is rewritten whole at each
  open (`store.replace`); two writers of one file would race.
- The preferences: a list of paths is no setting, and the writer would rewrite the whole preferences file at each page.
