# megaphone.kuber.studio

Static landing page for Megaphone. No build step or runtime dependencies are required; serve this directory as the web root.

## Local preview

```bash
python3 -m http.server 4173 --directory website
```

Then open `http://localhost:4173`.

## Design notes

- The real multi-app product recording lives at `assets/demo.gif`.
- Interface scenes are lightweight HTML/CSS reconstructions of Megaphone's Dictionary, cleanup pipeline, recording overlay, and app-aware output.
- The terminal switcher is adapted from interaction patterns in [brainless](https://github.com/theswerd/brainless), used under its MIT license (Copyright © 2026 Ben Swerdlow). No source code was copied from glasscn-components; it was used as visual research only because its repository does not currently include a license.
- Animation respects `prefers-reduced-motion` and all core content works without JavaScript.

## Deploy

Serve `website/` at `https://megaphone.kuber.studio/`. The canonical URL, sitemap, structured data, and download links already target that domain.
