# Stamps: text put on a page

## Purpose

Write on a page: a name in a field of a form that has no field, a date, "Paid", a note in the margin. The text goes on
top of the page, with a background that can hide what is under it, in a font the person picks.

## Decisions

- The Text tool (T, the toolbar's button): a click on a page places a new stamp there and opens its field; a click on a
  stamp opens it again. Enter commits, Escape gives up, a click elsewhere commits. An empty stamp committed is removed.
- While the tool is on, the toolbar shows the style: the family (sans, serif, mono: PDF's Helvetica, Times and Courier),
  bold, italic, the size, the colour of the text and of the background (none, white, yellow, black). The style applies
  to the stamp being edited and to the next ones.
- A stamp is part of its page's value (gt:pdf's `Page.stamps`), so it turns, moves and goes with its page, and each
  change is one undoable edit of the page's stamps.
- Where it goes: the point clicked on the page as shown is turned back into the page as its file shows it, and the stamp
  takes the turns that make it read upright there (`(4 - turns) % 4`).
- The worker measures each stamp (`pdf.stamp_size`) and puts its box, as shares of the page shown, in the snapshot: the
  interface hits stamps and places the field without calling the engine.
- The fonts are not embedded: every reader has them. Their characters are Western European ones (WinAnsi); another one
  is written as "?", and the field says so before the commit.

## Refused alternatives

- Changing the document's own words (feuille 0.3): the words of a PDF are glyphs of a font that often holds only the
  letters the document used, without reflow; the result was unreliable, and the new engine does not edit content.
- Embedding a system font for any script: a subset and a Type 0 font to write; later, if a person needs a script
  outside WinAnsi.
- A free-form annotation (`/FreeText`): readers draw it differently, and feuille hides annotations by default.
