package feuilletool

// The site, made when it is deployed (.github/workflows/pages.yml) so that it cannot be behind a release. The steps are
// the toolkit's (gt:site, its `site` command: build <site> <out>, check, card); this file says what this site is: its
// address, names and colours. {{version}} in the home page is the last version.

import tk_site "gt:site"
import toolbox "gt:toolbox"

VERSION_MARK :: "{{version}}"

@(rodata)
SITE_DOWNLOADS := [?]tk_site.Download{
	{os = "linux", label = "Linux", href = "https://github.com/sachahjkl/feuille/releases/download/v{{version}}/feuille-{{version}}-linux-x64.tar.gz", detail = "v{{version}} · x64 · .tar.gz"},
}

SITE_LD :: [?][2]string{
	{"applicationCategory", "BusinessApplication"},
	{"operatingSystem", "Linux"},
	{"license", "https://opensource.org/license/mit"},
}

site_meta :: proc() -> tk_site.Meta {
	m := tk_site.meta_default(name = "Feuille", url = "https://feuille.froment.software/", repository = REPOSITORY, tagline = "Open a PDF at once, arrange its pages, change its words", theme = "#100d0b", accent = "#f59a3c")
	@(static) ld := SITE_LD
	m.ld_fields = ld[:]   // (static: the site command keeps the Meta as long as the tool runs)
	m.shop = SHOP
	return m
}

// The shop: feuille's licence (src/licence), sold through Paddle by the toolkit's licence Worker. A licence supports the
// program; everything is in the one version without it (gui_toolkit docs/licence.md).
SHOP :: tk_site.Shop{
	name           = "Feuille",
	icon           = "../img/logo.png",
	product_title  = "Feuille User License",
	price          = "15&nbsp;&euro;",
	price_note     = "",
	environment    = "production",
	client_token   = "live_c259720f641c0ca14629c9d1543",   // Paddle's client-side token (public: it is in the page)
	edition        = "supporter",
	price_id       = "pri_01m7mjektq8b49e041ppps7tv3",
	worker         = "https://feuille-licence.sacha-42a.workers.dev",
	thanks         = "https://feuille.froment.software/thanks/",
	help           = REPOSITORY + "/issues/new",
	register       = "Open Feuille's settings (Ctrl+,), the <b>General</b> page, <b>Licence</b>: paste the key, or choose the file.",
	extension      = ".feuillelicence",
	repository     = REPOSITORY,
	seller         = tk_site.SELLER_FROMENT,
	code_licence   = "MIT License",
	platform       = "Linux, x64.",
	network        = tk_site.NETWORK_UPDATES_ONLY,
	stylesheet     = "../style.css",
	home           = "../",
	updated        = "2026-11-17",
}

site_command :: proc() -> toolbox.Command {
	return tk_site.command({meta = site_meta(), pages = {version_mark = VERSION_MARK, downloads = SITE_DOWNLOADS[:]}, images = tk_site.images_default()})
}
