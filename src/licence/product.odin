// What feuille's licence is to the toolkit's licence package (gt:licence, docs/licence.md): its name in the payload,
// its key's tag, what its signatures cover, its file and its edition. The program checks with it (licence.odin),
// feuilletool signs and checks with it (`feuilletool licence`), and the licence Worker has the same values (its
// products/feuille.jsonc).
package feuille_licence

import licence "gt:licence"

PRODUCT :: licence.Product{
	name           = "feuille",
	title          = "Feuille",
	version_tag    = "FEUILLE1",
	sign_context   = "feuille-licence-v1\n",
	file_extension = ".feuillelicence",
	// (`feuilletool licence keygen` makes the pair; empty until then: no licence of the real key is accepted)
	public_key     = "_OynJxGLRyyW2_FWoj1mQtlDkO83UY8wF1TvJBGwL_0",
	// (the development pair: its seed is public on purpose, feuilletool's dev_seed)
	dev_public_key = "mA6MWGlLlsRDP5CHEp-GZ-zG15M13teRS4g7Vb48Z2I",
	editions       = {0 = {id = "supporter", title = "Supporter"}},
}
