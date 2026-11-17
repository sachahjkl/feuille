//! feuilletool bench's hayro side: `hayro-bench <file.pdf> <out folder> <scale> [password]` renders each page's own
//! content (no annotation, no form widget: feuille's masked opening) with hayro on white at `scale` pixels per point
//! and writes `<out>/<page>.rgba` (two little-endian u32, width and height, then the straight RGBA pixels). One line per page on the standard output: `page <n> <ms>` or `fail <n> <why>`; `open
//! <why>` when the file does not open. A panic of one page is caught and told; the next page goes on.

use std::io::Write;
use std::panic;
use std::time::Instant;

use hayro::hayro_interpret::{InterpreterSettings, RenderContent};
use hayro::hayro_syntax::Pdf;
use hayro::vello_cpu::color::palette::css::WHITE;
use hayro::{PixmapSettings, RenderCache, RenderSettings, render};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 && args.len() != 5 {
        eprintln!("usage: hayro-bench <file.pdf> <out folder> <scale> [password]");
        std::process::exit(2);
    }
    let scale: f32 = args[3].parse().unwrap_or(1.0);
    let password = args.get(4).cloned().unwrap_or_default();
    let data = match std::fs::read(&args[1]) {
        Ok(d) => d,
        Err(e) => {
            println!("open {e}");
            return;
        }
    };
    // (a panic is told as a failure of its page: its message stays off the standard error's way)
    panic::set_hook(Box::new(|_| {}));
    let pdf = match panic::catch_unwind(|| Pdf::new_with_password(data, &password)) {
        Ok(Ok(pdf)) => pdf,
        Ok(Err(e)) => {
            println!("open {e:?}");
            return;
        }
        Err(_) => {
            println!("open panic");
            return;
        }
    };
    let cache = RenderCache::new();
    // (the page's own content, its annotations and form widgets not drawn: feuille's masked opening)
    let interpreter = InterpreterSettings { render_content: RenderContent::PAGE, ..InterpreterSettings::default() };
    let settings = RenderSettings::default();
    let pixmap_settings = PixmapSettings { x_scale: scale, y_scale: scale, bg_color: WHITE };
    let out = std::io::stdout();
    for (i, page) in pdf.pages().iter().enumerate() {
        let start = Instant::now();
        let result = panic::catch_unwind(panic::AssertUnwindSafe(|| {
            render(page, &cache, &interpreter, &settings, &pixmap_settings)
        }));
        let ms = start.elapsed().as_secs_f64() * 1000.0;
        match result {
            Ok(pixmap) => {
                let (w, h) = (pixmap.width() as u32, pixmap.height() as u32);
                let mut bytes = Vec::with_capacity(8 + (w * h * 4) as usize);
                bytes.extend_from_slice(&w.to_le_bytes());
                bytes.extend_from_slice(&h.to_le_bytes());
                // (on an opaque white page, premultiplied and straight alpha are the same bytes)
                bytes.extend_from_slice(pixmap.data_as_u8_slice());
                let _ = std::fs::write(format!("{}/{}.rgba", args[2], i), bytes);
                let _ = writeln!(out.lock(), "page {i} {ms:.2}");
            }
            Err(_) => {
                let _ = writeln!(out.lock(), "fail {i} panic");
            }
        }
    }
}
