package feuille

import "core:fmt"
import "core:strings"
import "core:testing"
import "gt:ui"

// Every preference of feuille's own has its line in docs/configuration.md.
@(test)
every_preference_is_documented :: proc(t: ^testing.T) {
	doc :: #load("../docs/configuration.md", string)
	for d in PREF_DEFS {
		testing.expectf(t, strings.contains(doc, fmt.tprintf("| `%s` |", d.name)), "docs/configuration.md has no line for %s", d.name)
	}
}

// The form layer stays hidden unless the settings say otherwise: the masked opening is the default.
@(test)
the_layer_is_hidden_by_default :: proc(t: ^testing.T) {
	for d in PREF_DEFS {
		if d.name == LAYER_PREF { testing.expect(t, !d.default.b, "view.form_layer is off by default") }
	}
}

// No two actions share a shortcut, and none takes the toolkit's debug chords (D, W, E with Ctrl+Alt+Shift).
@(test)
actions_shortcuts_do_not_collide :: proc(t: ^testing.T) {
	seen := make(map[ui.Chord]Action, context.temp_allocator)
	reserved := [?]ui.Chord{
		{.D, {.Ctrl, .Shift, .Alt}},
		{.W, {.Ctrl, .Shift, .Alt}},
		{.E, {.Ctrl, .Shift, .Alt}},
	}
	for a in Action {
		for k in ACTIONS[a].keys {
			if k.key == .None { continue }
			if prev, dup := seen[k]; dup {
				testing.expectf(t, false, "actions %v and %v share shortcut %v", prev, a, k)
			}
			seen[k] = a
			for r in reserved {
				testing.expectf(t, k != r, "action %v collides with reserved toolkit chord %v", a, r)
			}
		}
	}
	testing.expect_value(t, len(ACTIONS[.Density].keys), 1)
	testing.expect_value(t, ACTIONS[.Density].keys[0], ui.Chord{.R, {.Ctrl, .Shift, .Alt}})
}
