# Marks: text and shapes put on a page

## Purpose

Write and draw on a page: a name in a field of a form that has no field, a date, "Paid"; a box around a figure, a
circle around a word, an arrow to a line, a free note with the pen, a passage highlighted. The marks go on top of the
page and become part of it in the saved copy.

## Decisions

- The tools, one at a time (the toolbar's group, or a key): Text (T), Rectangle (R), Ellipse (E), Line (L), Arrow (A),
  Pen (P), Highlighter (H). Escape leaves the tool; the same key or button again too.
- Text: a click places a new text there and opens its field; a click on a text opens it again. Enter commits, Escape
  gives up, a click elsewhere commits. An empty text committed is removed.
- Shapes: a drag draws one, from where it starts to where it ends (the Pen follows the pointer; the Highlighter draws a
  box of translucent colour over what it covers). A drag too short to see draws nothing.
- With any tool on, a press on a mark selects it and a drag moves it; a click on a text opens it. The selected mark is
  outlined; Delete removes it; the style bar changes it at once.
- The style bar shows the tool's style: for text the family (sans, serif, mono: PDF's Helvetica, Times and Courier),
  bold, italic, the size, the colours of the words and of their background; for shapes the line's colour (or none),
  the fill (or none), the width; for the highlighter its colour. The style applies to the selected mark and to the
  next ones.
- A mark is part of its page's value (gt:pdf's `Page.stamps` and `Page.shapes`), so it turns, moves and goes with its
  page, and each change (made, moved, restyled, removed) is one undoable edit of the page's marks.
- Where it goes: a point on the page as shown is turned back into the page as its file shows it; a text takes the
  turns that make it read upright there (`(4 - turns) % 4`). Moved, a text reads upright where it lands.
- The worker measures each mark and puts it in the snapshot as shares of the page shown: a text's box, a shape's
  points and box. The interface hits, outlines and moves marks without calling the engine.
- The text fonts are not embedded: every reader has them. Their characters are Western European ones (WinAnsi);
  another one is written as "?".

## Refused alternatives

- Changing the document's own words (feuille 0.3): the words of a PDF are glyphs of a font that often holds only the
  letters the document used, without reflow; the result was unreliable, and the engine does not edit content.
- Annotations (`/FreeText`, `/Square`, `/Ink`, `/Highlight`): readers draw them differently, some do not print them,
  and feuille hides the annotation layer by default, so its own marks would vanish with it.
- A selection tool of its own: one more mode to enter before moving anything. With any marking tool on, a press on a
  mark is unambiguous.
