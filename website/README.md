# megaphone.kuber.studio

Static landing page for Megaphone. No build step or runtime dependencies are required; serve this directory as the web root.

## Local preview

```bash
python3 -m http.server 4173 --directory website
```

Then open `http://localhost:4173`.

## Design notes

- The hero is a generated, animated waveform field with a reconstruction of Megaphone's real recording overlay; it does not depend on video or GIF playback.
- The feature explorer mirrors Megaphone's native SwiftUI sidebar, Settings cards, Dictionary fields, toggles, and cleanup controls. The interactive Mail/Slack scene demonstrates active-window context, while the Hey Megaphone flow makes the on-device Foundation Models handoff explicit.
- The terminal switcher is adapted from interaction patterns in [brainless](https://github.com/theswerd/brainless), used under its MIT license (Copyright © 2026 Ben Swerdlow). No source code was copied from glasscn-components; it was used as visual research only because its repository does not currently include a license.
- Animation respects `prefers-reduced-motion` and all core content works without JavaScript.

## Deploy

Serve `website/` at `https://megaphone.kuber.studio/`. The canonical URL, sitemap, structured data, and download links already target that domain.
