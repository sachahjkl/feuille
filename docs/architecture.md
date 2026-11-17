# Architecture

feuille is one process and one window. The interface is built again at every frame from the program's data (gui_toolkit
is immediate-mode); the data changes only on the interface's thread. This page is the map of the code; the reasons
behind it (the decisions, the refused alternatives, the subtle points) are in [src/md](../src/md/README.md).

## Packages and files

| Where | What |
|---|---|
| `src/pdf/` | The PDF engine's binding (PDFium, opened with dlopen): open, render, the edits, save. One thread calls it. |
| `src/worker.odin` | The document's worker: it owns the engine and the open document; it loads, renders, edits and saves, and posts each answer (`ui.post`). |
| `src/edits.odin` | The edits the worker makes: turn, remove, add, import, move, extract, a text block's words, undo and redo. |
| `src/layout.odin` | The column of pages and the strip of thumbnails: each page's place, computed when the document or the zoom changes, never in a frame. |
| `src/app.odin` | The App: the window, its settings, the snapshot of the document, the pictures; `app_open`, `app_step`, `app_close` (the tests drive the same procedures). |
| `src/view.odin` | The window: the title bar and the window's buttons, the tools, the pages and the thumbnails, the password asked, the empty view, the status bar. |
| `src/actions.odin` | The table of every act (its id, label, keys, icon), what can act now, what each does; the confirmations; the palette's commands. |
| `src/program_actions.odin` | The suite's program commands: the window, the updates, About, the site, the look a key away; the document's file acts. |
| `src/palette_sources.odin` | The palette's own sources: `@` the pages, `/` the recent PDFs. |
| `src/menus.odin` | The context menu of a page and of a thumbnail; the menu of Open with. |
| `src/recent.odin` | The recent PDFs, each one's page and zoom: two stores of the state folder. |
| `src/launch.odin` | What starts another program or speaks to the desktop, on a task: the browser, the file manager, Open with and its applications, a new window, the desktop's recent files. |
| `src/integration.odin` | feuille on the desktop: its identity, the install's options, the menu's and the session's switches (`desktop_follow`), the single instance and its messages. |
| `src/settings.odin`, `src/settings_view.odin` | The preferences (the toolkit's standard ones and feuille's) and their page. |
| `src/updates.odin`, `src/licence.odin` | The toolkit's updater and licence, given feuille's product and words. |
| `src/system_<os>.odin` | What differs between the systems in the program itself (`SETUP_AT_START`). |
| `src/fixture/` | The tests' PDF writer: no binary file in the repository. |
| `tools/feuilletool/` | The project's commands: build, test, check, release, site, notices, logo, shots, bench. |

## Threads

- The interface's thread owns the App, the snapshot and the pictures. It reads no file and starts no program, but at
  the start, before the window shows: the preferences, the themes file, the memory of the documents, the last crash.
- The document's worker (`src/worker.odin`) makes every engine call. The newest render ask replaces the one waiting;
  an edit never does.
- `app.pool` runs what waits on the system (`src/launch.odin`); `app.desktop_pool`, one thread, applies the desktop's
  switches in their order. Each task gets copies, and posts its answer with `ui.post`; a window closed drops the answer
  and the task frees what it held.
- The single instance's server has its own thread (gt:instance); a message is copied and posted to the interface.
- The preferences, the views, the palette's choices, the file dialogs' memory and the documents' memory are written by
  their own writers' threads (gt:config, gt:store).

## Tests

`src/app_test.odin` opens the real program with no window of the system (`app_open({headless = true})`), on PDFs the
tests write (`src/fixture`). Headless, nothing of the person's is read or written, and nothing starts: what a launch
would have started is in `app.opened`. `src/shots_test.odin` makes the README's pictures (`feuilletool shots`).
