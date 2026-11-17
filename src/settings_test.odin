package feuille

import "core:fmt"
import "core:strings"
import "core:testing"

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
