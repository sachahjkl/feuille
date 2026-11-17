# The snapshot

## Purpose

The interface needs the shape of the document to lay out the column (the page sizes) and to name the pictures it shows.
It must not call the engine for it. The snapshot is that shape, made by the worker and posted whole.

## Shape

- `revision`: grows with each change of the document (open, edit, undo).
- `pages`: one entry per page, in order: its identity, its size in points, its rotation in quarter turns.
- `name`, `path`, `edited` (a change since the open or the last save), `can_undo`.

## Decisions

- A page's identity is a number the worker gives it once (open, insert) and never reuses. It follows the page through
  moves. The picture cache keys on (identity, page revision, zoom, layer), where the page revision changes only when
  that page's content or rotation changes. A reorder re-renders nothing; a turn re-renders one page.
- The snapshot is immutable once posted. The interface swaps the old one for the new one in the posted call and frees
  the old one. No lock.
- The layout (each page's top in the column, the total height) is computed when a snapshot or the zoom changes, then
  kept. A frame finds the visible pages by a binary search over the tops: no pass over every page.

## Refused alternatives

- The interface asks the worker for a page's size when it needs it: a round trip per page and a layout that jumps.
- A shared document behind a lock: the interface would wait on a long render.
