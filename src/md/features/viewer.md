# The viewer

## Purpose

Read a document as a column of pages: scroll, zoom, move by page with the keyboard. It answers at once whatever the
size of the document.

## Decisions

- One scroll region holds the column. Each page is a box of its laid-out size; a page without its picture shows a
  plain sheet of the page's size, so the layout never jumps when the picture comes.
- Zoom: fit to the width (default), or a factor. Ctrl+wheel and Ctrl+plus/minus change it; Ctrl+0 fits the width again.
  The zoom keeps the point under the pointer (or the top of the view) in place.
- Pictures are rendered at the zoom times the screen's scale, in device pixels: sharp at any scale. The renders asked
  are the visible pages and one page beyond each edge, the nearest to the centre first.
- The cache holds pictures up to a budget of bytes (the oldest seen go first). A stale picture (other zoom, older page
  revision) stays drawn, stretched, until the new one comes.
- A render ask carries the list of wanted pictures. A newer ask replaces a waiting one: when the person scrolls fast,
  the worker renders where the view is, not where it was.

- The thumbnails are a second column with a layout of their own (the same code, the strip's width, no zoom). Their
  pictures are asked with the pages' in one list and kept in a cache of their own; they draw the pages' own content,
  never the layer.
- After an edit, only the pages whose content version moved (a turn, a text edit) are rendered again: a move or a
  removal re-renders nothing.

## Subtleties

- The worker renders one page at a time and checks for a newer ask between pages, so a long list never delays the
  pages that came into view.
- A picture larger than the texture limit is not rendered whole: the zoom is capped so a page fits (the cap is told in
  the zoom's label).
