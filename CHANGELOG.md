# Changelog

All notable changes to Megaphone are documented here. Megaphone is a fork
of [FreeFlow](https://github.com/zachlatta/freeflow); entries below 1.0.0
are inherited FreeFlow history.

This project uses semantic versioning for public releases. Use `MAJOR.MINOR.PATCH`, where:

- `MAJOR` changes include breaking behavior or major compatibility changes.
- `MINOR` changes add user-visible features and improvements.
- `PATCH` changes fix bugs, polish existing behavior, or make small internal improvements.

## [1.1.7] - 2026-07-21

### Added

- Transforms: say “Hey Megaphone, polish that” to tighten your last dictation, or “prompt that” to restructure it as a clear AI prompt — plus your own named rewrite templates, managed next to Voice Macros. Entirely on-device.
- “Scratch that” (or “delete that”) spoken as a whole utterance deletes the dictation you just made, safely: nothing is deleted if the cursor moved. Toggleable in Settings.
- Revert Last Cleanup in the menu bar restores exactly what you said when the smart cleanup over-edited, replacing the cleaned text in place.
- Mouse-button push-to-talk (off by default): bind the middle or a side mouse button as a hold-to-talk trigger. The bound click never reaches the app under the cursor.
- A per-app Writing Style dial — Casual, Balanced, or Formal for Email, Work chat, Personal chat, Documents, and everything else. Balanced keeps today's behavior exactly; the dial adjusts register, never meaning.
- Dictionary entries can be starred and are ranked by real usage, so the terms you actually rely on always reach the model.
- The cancel key is now rebindable (Escape remains the default).

### Improved

- Dictating mid-sentence now continues the surrounding text naturally: lowercase continuations after an unfinished clause, a fresh capitalized sentence after a period, and never a repeat of words already on screen.

## [1.1.6] - 2026-07-21

### Added

- Ask Megaphone can now read the visible window, entirely on-device: requests like “reply to this email” or “answer his question” use the text on screen as reference. The accessibility tree is read first, with Vision OCR of the focused window as a fallback when Screen Recording is already granted — nothing ever leaves your Mac. Controlled by a new “Use on-screen text as context” toggle (on by default).
- Formatting now adapts to the app you're dictating into. Markdown-native surfaces like Obsidian, Notion, and GitHub get markdown lists and structure; chat apps stay plain text; documents welcome lists. Dictated “bullet point …” markers become real list lines, and a clear “first…, second…, third…” enumeration in a document formats itself as a list.

### Fixed

- WhatsApp and Telegram now count as casual chat instead of general writing, and a window title that merely contains an email address no longer masquerades as webmail context.
- Ask Megaphone responses no longer leak XML wrappers or echo prompt sections back into your text, and “make that a bulleted list” reliably replaces the dictation it refers to.
- Follow-up wake commands replace the intended earlier dictation more reliably.

### Removed

- All legacy cloud plumbing inherited from FreeFlow is gone — roughly 2,600 lines including API-key handling, cloud endpoints, and cloud model defaults. The only remaining network calls are the GitHub updater and the repo star count. Command mode no longer asks for Screen Recording permission, which only the removed cloud screenshot path needed.

## [1.1.5] - 2026-07-17

### Added

- Hey Megaphone can use a recent dictation from the same app and window, so follow-ups such as “make that formal” or “format that as a list” work without repeating the text.
- Smart Cleanup, Edit Mode, and Hey Megaphone now adapt their writing style for email, work chat, casual chat, documents, and technical apps using local app and window context.
- The new Megaphone website is available at [megaphone.kuber.studio](https://megaphone.kuber.studio), with release-aware downloads, installation help, and automatic updates when a new version ships.

### Improved

- Wake phrase recognition now handles “mega phone” as separate words and additional common SpeechAnalyzer variations while keeping the shorter plain “Megaphone” trigger optional.
- App-aware writing recognizes Mail, Outlook, Gmail, Slack, Teams, Discord, Messages, document editors, terminals, and code editors, including Slack and Discord in a browser.
- Recent-text follow-ups no longer borrow text from another window in the same application.

### Fixed

- Hey Megaphone results no longer paste stray `<response>` tags.
- App-specific context now reaches Edit Mode as well as Smart Cleanup and Inline AI.
- Update checks now use Megaphone’s release manifest instead of GitHub’s shared unauthenticated API quota, preventing false “GitHub returned status 403” failures on rate-limited networks.
- The GitHub API remains available as a fallback and reports a clear rate-limit message with the local reset time when GitHub rejects a request.
- Hey Megaphone and Edit Mode no longer fail with an unsupported-language error when app-aware context contains a macOS bundle identifier.

## [1.1.4] - 2026-07-15

### Fixed

- Opening Megaphone on macOS 15 or earlier now shows a clear message that macOS 26 (Tahoe) is required, with a button that opens Software Update, instead of Launch Services rejecting the app with the opaque error -10825. The app now starts through a small launcher that hands off to the real Megaphone binary on macOS 26 and later. (#1)

## [1.1.3] - 2026-07-15

### Added

- Inline AI (Alpha): hold the normal dictation shortcut and begin with “Hey Megaphone” to ask a question or generate text directly in the active app, powered entirely by Apple's on-device Foundation Models framework.
- Inline AI can now use a recent dictation in the same app as context, so follow-ups such as “Hey Megaphone, make that formal” rewrite the sentence you just entered.
- An optional shorter “Megaphone” trigger and a master switch to turn Inline AI off completely.

### Improved

- SpeechAnalyzer is biased toward the Megaphone wake phrases and safely recognizes common leading variations such as “mega phone,” “made a phone,” and “he made a phone.” These aliases never rewrite ordinary words in the middle of dictation.

### Fixed

- Wake-prefixed requests now strip the trigger and enter the command pipeline instead of being pasted as literal dictation.

## [1.1.2] - 2026-07-14

### Added

- A personal Dictionary for names, products, acronyms, and technical terms, with manual entry, search, enable/disable controls, and exact heard-to-written corrections.
- Conservative on-device learning that suggests unusual terms from successful dictations and activates them after three observations. Suggestions can be accepted, dismissed, disabled, or removed at any time.
- Existing Custom Vocabulary entries migrate automatically into the Dictionary and continue steering both SpeechAnalyzer and Smart Cleanup.

### Changed

- The README demo now uses a real high-resolution recording across Claude Code, Codex, Cursor CLI, and Google Docs, with production cuts and a focused Megaphone overlay animation.

### Fixed

- In-app updates now work with macOS App Management, validate the downloaded publisher and version, retain a verified rollback copy, and write durable recovery logs.
- Dictionary learning ignores failed cleanup, commands, macros, Exact mode, common prose, standalone numbers, and dismissed suggestions so recognition does not reinforce one-off mistakes.

## [1.1.1] - 2026-07-14

### Added

- Smart Cleanup powered by Apple's on-device Foundation Models framework. Megaphone prewarms a fresh private session while recording, then removes fillers, resolves self-corrections, and improves punctuation before pasting.
- Basic Cleanup, an instant deterministic fallback that removes conservative filler and stutter patterns without a language model.
- Explicit heard-to-written corrections such as `mega phone -> Megaphone`, applied to Basic Cleanup and supplied as required spellings to Smart Cleanup.
- Restored on-device cleanup instructions and app-context hints, including user-defined trigger phrases and formatting preferences.
- Restored Output Language and Edit Mode using the on-device model, with safe fallbacks when Apple Intelligence is unavailable.
- Added a non-blocking Apple Intelligence readiness step for new installs and a one-time upgrade prompt when Smart Cleanup is selected but Apple Intelligence is disabled. Users can open System Settings or continue with Basic Cleanup.

### Changed

- Cleanup now has Smart, Basic, and Exact modes. Smart is the default; model errors, unsupported languages, timeouts, and unavailable Apple Intelligence fall back to Basic without blocking dictation.
- Custom Vocabulary now steers SpeechAnalyzer recognition and smart cleanup spelling.
- Local cleanup context uses active-app metadata without capturing screenshots or requesting Screen Recording permission.
- Fresh setup no longer asks for obsolete Screen Recording permission.
- Run Log reports which cleanup path ran and records Smart Cleanup latency or fallback reasons.
- The Smart Cleanup prompt now preserves hedging and complete technical clauses while strictly resolving explicit self-corrections and refusing to execute dictated instructions.

### Fixed

- Smart sessions are isolated per dictation and discarded on cancellation, preventing context from leaking between recordings.
- Model output is rejected when it is empty, assistant-like, or unexpectedly expands the dictated text.
- In-app updates now replace the installed bundle safely under macOS App Management, verify the expected publisher and version, preserve a validated rollback copy, and keep a durable updater log when recovery is needed.

## [1.1.0] - 2026-07-14

### Changed

- New app icon.
- The menu bar icon is now hidden by default. Re-open the app (e.g. from Spotlight) to reach Settings, where it can be turned back on.
- **Fully local:** the Prompts tab, Cleanup, Output Language, and Edit Mode settings are gone, along with the Edit Mode setup step and the "API key required to test" prompt harnesses. Edit Mode is disabled since it depended on the retired LLM layer. Dictation, voice macros, custom vocabulary, and everything else run entirely on-device.

## [1.0.3] - 2026-07-14

### Removed

- The API key and provider configuration UI is gone from Settings — Megaphone is now fully on-device end to end, with no cloud option surfaced anywhere. (The LLM cleanup layer remains dormant in the codebase for a possible on-device Apple Foundation Models port.)

## [1.0.2] - 2026-07-14

### Removed

- The API key step is gone from setup entirely — Megaphone works out of the box with on-device transcription. An LLM key for optional AI cleanup can still be added in Settings.

### Fixed

- The Accessibility setup step no longer hard-blocks: it explains that macOS can pin a permission grant to a previous version of the app (remove Megaphone from the Accessibility list and re-add it), and adds a "Continue anyway" escape hatch. Same for Screen Recording.
- Releases are now signed with a persistent signing identity instead of ad-hoc, so macOS permission grants (Accessibility, Microphone, Screen Recording) survive app updates. One final re-grant is needed when updating to this version.

## [1.0.1] - 2026-07-14

### Fixed

- The DMG installer window now uses Megaphone's dark liquid-glass background instead of the broken FreeFlow artwork with clipped text.
- The setup welcome card now shows the Megaphone maintainer's GitHub avatar instead of a hardcoded upstream avatar.
- The API key step in setup is now clearly optional and skippable — transcription is fully on-device, and the key only powers AI cleanup and app context. Megaphone dictates fine without one.

## [1.0.0] - 2026-07-14

First Megaphone release, forked from FreeFlow 1.1.0.

### Changed

- **Renamed to Megaphone**, with a new liquid-glass monochrome megaphone icon.
- **Transcription now runs entirely on-device** via Apple's SpeechAnalyzer (requires macOS 26). Audio is analyzed while you speak, so the transcript is ready almost instantly when you stop — and recordings never leave your Mac. The cloud transcription stack (transcription provider/model settings, transcription API URL and key, realtime WebSocket streaming, and background HTTP pre-transcription) has been removed; the configured API key is now used only for LLM cleanup and app context.
- The transcription language picker now lists the languages supported by the on-device speech model, and Settings shows the model's install status with a download button.
- Custom vocabulary now also biases the on-device speech model directly (via analyzer contextual strings), in addition to guiding LLM cleanup.

### Added

- The recording start, stop, and error feedback sounds are now configurable in Settings, with a picker and preview button for each event across the full set of built-in macOS alert sounds.

## [1.1.0] - 2026-06-03

### Added

- Model pickers in Settings for post-processing, fallback, context, and transcription models, including Qwen 3 32B and custom model entries.
- A recording overlay display picker for choosing the active window, primary display, or a specific connected monitor.
- In-pill error notifications so transient failures such as network or provider errors are visible without opening logs.
- Advanced timeout overrides for local model and slow network setups.

### Improved

- Retried dictations now place the successful transcript on the clipboard and update Paste Again.
- Paste Again now preserves the latest raw transcript earlier in the dictation flow, so it remains useful if later cleanup or pasting fails.
- Post-processing handles reasoning-oriented model output more cleanly, including Qwen thinking tags and providerless model aliases.

### Fixed

- Fixed cases where transcription could hang indefinitely when a provider accepted a connection but never returned a response.
- Fixed false screen-recording permission alerts from unrelated permission messages.
- Fixed duplicate in-pill error notifications being dismissed by an older timer.

## [1.0.0] - 2026-05-20

FreeFlow is now considered feature-complete and stable enough for a 1.0 release.

### Added

- Paste Again shortcut for re-pasting the most recent dictation.
- Recent transcript history in the menu bar, with copy actions for quickly reusing previous dictations.
- Run Log copy controls for both literal and cleaned transcript output.
- Menu bar actions for opening the Run Log and checking for updates.
- Debug settings for troubleshooting overlays and update prompts.
- A polished drag-to-Applications DMG background for installer builds.

### Improved

- Recording feedback now uses a cleaner minimalist menu-bar overlay, with clearer command-mode state.
- Transcribing and processing feedback appears sooner and more consistently after recording stops.
- Shortcut labels now use friendlier modifier names alongside symbols.
- Setup and recovery flows are more resilient when restoring app state.
- Sentence-ending dictations now paste with trailing spacing that better matches normal writing.
- Development builds and main-branch release automation are easier to identify and validate.

### Fixed

- Fixed shortcut collision checks for edit mode and manual modifier bindings.
- Fixed cases where dictation could terminate automatically while still in progress.
- Fixed clipboard restoration after dictation when the original clipboard content is unchanged.
- Marked transient dictation clipboard contents so clipboard managers can avoid saving them.
- Preserved spoken instructions verbatim during post-processing.
- Simplified transcription submission errors into clearer one-line messages.

## [0.3.3] - 2026-04-25

### Added

- Output Language setting for automatically translating dictated text before it is pasted.
- Transcription Language setting for choosing the language FreeFlow listens for during dictation.
- Recording state flag file for external tools that need to know when FreeFlow is actively recording.
- Distinct FreeFlow Dev app and menu bar icons so development builds are easier to tell apart from release builds.

### Improved

- Permission prompts and setup screens now use the correct app name for the installed build.
- Release notes in update prompts now render changelog formatting more clearly.
- Development builds now have clearer bundle naming and icon handling.

### Fixed

- Fixed audio recording crashes caused by unexpected input formats, resampling, and upload-path conversion.
- Fixed cases where FreeFlow could silently fall back when the selected microphone was unavailable.
- Fixed paste shortcuts on Colemak-DH and other non-QWERTY keyboard layouts.
- Fixed output language handling when custom system prompts are enabled.

## [0.3.2] - 2026-04-23

### Fixed

- Removed the pause-based audio interruption mode that could misfire and resume playback unexpectedly; dictation now only mutes audio.

## [0.3.1] - 2026-04-23

### Added

- Faster live dictation with realtime transcription support.
- A setting for choosing the realtime transcription model.
- Run log exports, so you can save a full dictation run for debugging or sharing.
- A Copy Transcript action in the run log.
- A voice command for submitting text: say "press enter" at the end of a dictation.
- Audio controls that can mute or pause other audio while you dictate, then restore it when recording stops.
- Build details in Settings for easier troubleshooting.
- Direct shortcuts from FreeFlow to the right macOS permission settings.
- A What’s New popup when an update is available.

### Improved

- Recording feedback now feels more responsive.
- The run log is easier to scan and use.
- Exported run logs include more useful context for reproducing issues.
- Realtime transcription is more reliable when recordings are cancelled, retried, or finish with no text.
- Provider settings are easier to edit without accidental whitespace or half-saved values.
- FreeFlow now warns you if alert sounds may be hard to hear because system audio is muted or very low.
- Update prompts now show the version, release date, and release notes more clearly.
- FreeFlow now uses proper version numbers for updates instead of internal build names.

### Fixed

- Fixed cases where arrow or navigation keys could be mistaken for Fn shortcut input.
- Fixed a clipboard timing issue that could paste the wrong content.
- Fixed empty realtime transcriptions getting stuck instead of finishing cleanly.
- Fixed waveform glitches caused by invalid audio levels.
- Filtered out more common transcription artifacts.
- Fixed alert sound hints staying visible after alert sounds are turned off.
- Fixed update checks so users only see real app releases, not internal builds.
- Fixed update checks so the app does not offer an older or already-installed version.
