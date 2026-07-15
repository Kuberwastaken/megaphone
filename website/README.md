# megaphone.kuber.studio

Static landing page for Megaphone. No build step or runtime dependencies are required; serve this directory as the web root.

## Local preview

```bash
python3 -m http.server 4173 --directory website
```

Then open `http://localhost:4173`.

## Design notes

- The first viewport is a generated waveform field with Megaphone's real recording overlay and no oversized app artwork. It does not depend on video or GIF playback.
- Hero proof points state that Megaphone is free, MIT-licensed, private, and requires macOS 26 on Apple silicon. The GitHub star count refreshes from the public repository API with a static fallback.
- The feature bento demonstrates a paced, auto-scrolling Smart Cleanup stream, a three-row locale wall sourced from `SpeechTranscriber.supportedLocales`, and paired macOS-style Dictionary and Memory windows. The locale illustration currently reflects the 30 downloadable locales reported by the target Mac. Mail and Slack alternate automatically to demonstrate active-window context, while the Hey Megaphone response appears only after its section crosses the scroll threshold.
- The compact recording surface follows `RecordingOverlay.swift`: a translucent 92-point surface with a centered nine-bar waveform. In the hero, those bars and the background field share one animation clock. The agent demo advances through Claude Code, Codex, and Cursor based on scroll progress.
- The terminal switcher is adapted from interaction patterns in [brainless](https://github.com/theswerd/brainless), used under its MIT license (Copyright © 2026 Ben Swerdlow). No source code was copied from glasscn-components; it was used as visual research only because its repository does not currently include a license.
- Animation respects `prefers-reduced-motion` and all core content works without JavaScript.

## Deploy

Serve `website/` at `https://megaphone.kuber.studio/`. The canonical URL, sitemap, structured data, and download links already target that domain.
