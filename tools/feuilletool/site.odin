package feuilletool

// The site, made when it is deployed (.github/workflows/pages.yml) so that it cannot be behind a release. The steps are
// the toolkit's (gt:site, its `site` command: build <site> <out>, check, card); this file says what this site is: its
// address, names and colours, and its own check of the downloads. {{version}} in the home page is the last version.

import "core:fmt"
import json "gt:json"
import tk_site "gt:site"
import toolbox "gt:toolbox"

VERSION_MARK :: "{{version}}"

@(rodata)
SITE_DOWNLOADS := [?]tk_site.Download{
	{os = "windows", label = "Windows", href = "https://github.com/sachahjkl/feuille/releases/download/v{{version}}/feuille-{{version}}-windows-x64.zip", detail = "v{{version}} · Windows 10 / 11 · x64 · .zip"},
	{os = "linux", label = "Linux", href = "https://github.com/sachahjkl/feuille/releases/download/v{{version}}/feuille-{{version}}-linux-x64.tar.gz", detail = "v{{version}} · x64 · .tar.gz"},
}

SITE_LD :: [?][2]string{
	{"applicationCategory", "BusinessApplication"},
	{"operatingSystem", "Windows, Linux"},
	{"license", "https://opensource.org/license/mit"},
}

site_meta :: proc() -> tk_site.Meta {
	m := tk_site.meta_default(name = "Feuille", url = "https://feuille.froment.software/", repository = REPOSITORY, tagline = "Open a PDF at once, arrange its pages, put text on them", theme = "#100d0b", accent = "#f59a3c")
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
	platform       = "Windows 10 or 11, x64, and Linux, x64.",
	network        = tk_site.NETWORK_UPDATES_ONLY,
	stylesheet     = "../style.css",
	home           = "../",
	updated        = "2026-11-17",
}

site_command :: proc() -> toolbox.Command {
	return tk_site.command({meta = site_meta(), pages = {version_mark = VERSION_MARK, downloads = SITE_DOWNLOADS[:]}, extra = site_downloads, images = tk_site.images_default()})
}

// A browser of each system (what it says it runs on), and the download the home page offers it: the file of the
// button, and the other system's in the line under it. A phone gets the first of SITE_DOWNLOADS: whoever reads it there
// installs it on a computer.
@(private = "file")
Site_System :: struct { name, agent, platform, data, button, other: string }

@(private = "file", rodata)
SITE_SYSTEMS := [?]Site_System{
	{"Windows", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", "Win32", "Windows", "-windows-x64.zip", "-linux-x64.tar.gz"},
	{"Linux", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36", "Linux x86_64", "Linux", "-linux-x64.tar.gz", "-windows-x64.zip"},
	{"Android", "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36", "Linux armv8l", "Android", "-windows-x64.zip", "-linux-x64.tar.gz"},
}

// The site check's own step: the home page, as each system's browser sees it, offers that system's file.
site_downloads :: proc(s: ^tk_site.Check) {
	for sys in SITE_SYSTEMS {
		tk_site.check_call(s, "Emulation.setUserAgentOverride", fmt.tprintf(`{{"userAgent":%s,"platform":%s,"userAgentMetadata":{{"platform":%s,"platformVersion":"","architecture":"x86","model":"","mobile":false}}}}`,
			json.quote(sys.agent), json.quote(sys.platform), json.quote(sys.data)))
		if !tk_site.check_go(s, "index.html") { continue }
		// (the button shown: the one with a box)
		button :: `[...document.querySelectorAll('.hero [data-download-os]')].find((e) => e.getClientRects().length > 0)`
		other :: `[...document.querySelectorAll('.hero [data-download-others]')].find((e) => e.getClientRects().length > 0).querySelector('a')`
		tk_site.check_expect(s, tk_site.check_true(s, fmt.tprintf(`%s.href.endsWith(%s)`, button, json.quote(sys.button))),
			fmt.tprintf("index.html, %s: the button is %s (%s)", sys.name, sys.button, tk_site.check_text(s, button + ".href")))
		tk_site.check_expect(s, tk_site.check_true(s, fmt.tprintf(`%s.href.endsWith(%s)`, other, json.quote(sys.other))),
			fmt.tprintf("index.html, %s: the other is %s (%s)", sys.name, sys.other, tk_site.check_text(s, other + ".href")))
	}
	tk_site.check_call(s, "Emulation.setUserAgentOverride", `{"userAgent":""}`)   // (the browser's own again)
}
