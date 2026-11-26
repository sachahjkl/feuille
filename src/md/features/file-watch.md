# The document followed on the disk

## Purpose

Another program can write the PDF that feuille shows: a printer driver, a LaTeX build, a sync client. Without help, the
person sees an old version and does not know it. feuille follows the document's file and opens the new version.

## Decisions

- **The folder is followed, not the file** (`fsx.Watch`). A program that saves often writes a temporary file and
  renames it over the old one: a watch on the file itself would follow the old file, gone. The folder sees the rename.
- **A change is the file's stamp, not an event.** Each change in the folder is compared with the stamp that the worker
  took when it read the file or wrote it (`Snapshot.stamp`). Another file of the folder, or feuille's own save over the
  original, opens nothing again.
- **The stamp is taken before the read.** A write that ends between the stamp and the read gives a newer stamp in the
  next event: the file is read again, never kept stale.
- **A document without edits opens again; an edited one is not touched.** The edits are a list over the version read
  (page-edits.md): applied to another version, they can point at pages that are not there. The status bar says that the
  file changed, and the edits stay on the version opened before. A save writes the version shown, as before.
- **A failed read keeps the document shown** (`app_open_file`): a file read in the middle of another program's write
  says so, and the end of that write opens it again.
- **One thread of its own waits** (`watch_wait` blocks). It stats the file, never the interface's thread. Where the
  system has no watcher, `watch_open` fails, the thread ends, and nothing is followed.

## Refused

- **Polling the file's stamp on a timer.** It wakes the program for nothing and is late by its period.
- **A question in a dialog ("Open again?").** For a document without edits, nothing is lost by opening it again; a
  question there only interrupts.
