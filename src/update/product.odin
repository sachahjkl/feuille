// What feuille is to the toolkit's update package (gt:update, docs/updates.md): its name in the manifests and the
// release's file names, what its signatures cover, and the public half of its update key (`feuilletool update keygen`;
// the private half is in secrets/production.yaml and the release workflow's secret UPDATE_SIGNING_KEY).
package feuille_update

import update "gt:update"

PRODUCT :: update.Product{
	name         = "feuille",
	sign_context = "feuille-update-v1\n",
	public_key   = "SKp-w9Kfz96jri-LT_Cze4P0Mukd_Wq5bh-vvi8f8fA",
}
