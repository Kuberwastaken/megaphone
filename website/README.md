# megaphone.kuber.studio

Static landing page for Megaphone. No build step or runtime dependencies are required; serve this directory as the web root.

## Local preview

```bash
python3 -m http.server 4173 --directory website
```

Then open `http://localhost:4173`.

## Design notes

- The first viewport is a generated waveform field with Megaphone's real recording overlay and no oversized app artwork. It does not depend on video or GIF playback.
- The feature bento demonstrates token-by-token Smart Cleanup, language switching from `SpeechTranscriber.supportedLocales`, macOS-style Dictionary controls, and locally learned Memory. The locale illustration currently reflects the 30 downloadable locales reported by the target Mac. Mail and Slack alternate automatically to demonstrate active-window context, while the scroll-triggered Hey Megaphone flow makes the on-device Foundation Models handoff explicit.
- The compact recording surface follows `RecordingOverlay.swift`: a translucent 92-point surface with a centered nine-bar waveform. The agent demo advances through Claude Code, Codex, and Cursor based on scroll progress.
- The terminal switcher is adapted from interaction patterns in [brainless](https://github.com/theswerd/brainless), used under its MIT license (Copyright © 2026 Ben Swerdlow). No source code was copied from glasscn-components; it was used as visual research only because its repository does not currently include a license.
- Animation respects `prefers-reduced-motion` and all core content works without JavaScript.

## Deploy

Serve `website/` at `https://megaphone.kuber.studio/`. The canonical URL, sitemap, structured data, and download links already target that domain.
