<p align="center">
  <img src="Resources/AppIcon-Source.png" width="128" height="128" alt="Megaphone icon">
</p>

<h1 align="center">Megaphone</h1>

<p align="center">
  A free, open-source dictation app for macOS that runs <b>entirely on your Mac</b>,<br>
  powered by Apple's SpeechAnalyzer and Foundation Models frameworks.
</p>

<p align="center">
  <a href="https://github.com/Kuberwastaken/megaphone/releases/latest/download/Megaphone.dmg"><b>⬇ Download Megaphone.dmg</b></a><br>
  <sub>Requires macOS 26 (Tahoe) on Apple silicon</sub>
</p>

---

<p align="center">
  <img src="Resources/demo.gif" alt="Megaphone demo" width="600">
</p>

<div align="center">

Hold `Fn`, speak, and let go. Megaphone types the result into whatever app you're using.

</div>

---

## One-line install

```bash
curl -L -o /tmp/Megaphone.dmg https://github.com/Kuberwastaken/megaphone/releases/latest/download/Megaphone.dmg && xattr -c /tmp/Megaphone.dmg && hdiutil attach /tmp/Megaphone.dmg -nobrowse -mountpoint /tmp/megaphone-dmg -quiet && rm -rf /Applications/Megaphone.app && ditto /tmp/megaphone-dmg/Megaphone.app /Applications/Megaphone.app && hdiutil detach /tmp/megaphone-dmg -quiet && rm /tmp/Megaphone.dmg && open /Applications/Megaphone.app
```

Downloads the latest release, clears the [quarantine flag](#installing-manual), installs to /Applications, and launches — all in one paste:


## Why I built this

I came across [Inscribe's benchmark of Apple's new Speech APIs](https://get-inscribe.com/blog/apple-speech-api-benchmark.html) while scrolling Hacker News yesterday, and the results caught me off guard.

Across 5,559 LibriSpeech utterances, Apple's new **SpeechAnalyzer** reached a **2.12% word error rate**. That beat Whisper Small at 3.74%, Whisper Base at 5.42%, and Apple's older `SFSpeechRecognizer` at 9.02%. It also ran roughly **three times faster than Whisper Small**, completely on-device.

Apple had quietly shipped a genuinely excellent speech model as part of macOS, but very few apps seemed to be using it. Meanwhile, many dictation apps were still charging monthly subscriptions to send recordings to cloud-hosted Whisper APIs.

That felt a little silly, so I built Megaphone.

Megaphone is a fork of the excellent [FreeFlow](https://github.com/zachlatta/freeflow). I removed its cloud transcription stack and rebuilt that part of the app around Apple's SpeechAnalyzer.

## Installing-Manual

1. [Download Latest Megaphone.dmg](https://github.com/Kuberwastaken/megaphone/releases/latest/download/Megaphone.dmg).
2. Read the section below, because macOS is about to call this app malware.
3. Open the DMG and drag Megaphone into your Applications folder.
4. Launch it, walk through setup, and grant the microphone and accessibility permissions.
5. Hold `Fn` and start talking. Apple's speech model for your language downloads automatically the first time you use it.

If your Mac is on macOS 15 or earlier, Megaphone opens with a message explaining that macOS 26 is required — SpeechAnalyzer only exists on macOS 26 (Tahoe) and later, so there is unfortunately no way to support older systems.

Getting macOS to *not* scream about an app requires notarization, and notarization requires a $99/year Apple Developer membership. Sooo

**Option 1 — one command.** Clear the quarantine flag before opening the DMG:

```bash
xattr -d com.apple.quarantine ~/Downloads/Megaphone.dmg
```

**Option 2 — clicking things.** Open the app once, dismiss the warning, then go to System Settings → Privacy & Security, scroll down, and hit **Open Anyway**.

**Option 3 — trust no one.** [Build it from source](#building-from-source). Locally built apps skip the warning entirely.

Releases *are* signed with a persistent certificate, so macOS permissions you grant survive updates

## Features

* **Fully on-device transcription** — Apple's speech model processes your audio directly on your Mac. There is no transcription API, API key, or internet connection required.
* **Results as soon as you stop speaking** — Megaphone streams audio into the analyzer while you're talking, so most of the work is already done by the time you release the shortcut.
* **Hold-to-talk or toggle mode** — hold `Fn` to dictate, or press `Command-Fn` to start and stop recording. Both shortcuts can be changed.
* **Smart on-device cleanup** — Apple's Foundation Models framework removes fillers, resolves self-corrections, and fixes punctuation without uploading your transcript. Setup checks whether Apple Intelligence is ready and can open its System Settings pane; a deterministic Basic mode is always available as a fast fallback.
* **Inline AI (Alpha)** — hold your dictation shortcut and begin with “Hey Megaphone” to ask a question, generate text, or transform the sentence you just dictated (for example, “make that formal”). Megaphone uses recent text and active-app context on device. The shorter “Megaphone” trigger is optional, and common recognition slips are handled automatically.
* **A personal Dictionary** — add names and technical terms yourself, or let Megaphone learn the words you use often. Exact corrections and trigger phrases handle the stubborn edge cases.
* **Multiple languages** — choose any language supported by Apple's on-device model. Megaphone handles the required model downloads from Settings.
* **Plenty of settings** — configure shortcuts, sounds, the recording overlay, clipboard behaviour, voice macros, prompts, and more.

## Why it feels fast

There are two Apple models in the loop, but Megaphone does its best not to make you wait around for either of them.

**SpeechAnalyzer** listens as you speak instead of starting after you let go of `Fn`. At the same time, Megaphone prewarms Apple's on-device **Foundation Models** language model. By the time you finish a sentence, transcription is mostly done and the cleanup model is already awake.

Smart Cleanup gets the literal transcript and does the bits that need some judgement: dropping abandoned starts, understanding “Thursday — no, Wednesday,” preserving technical syntax, and leaving your actual meaning alone. Short dictations have a tight 2.5-second cleanup budget; longer ones get up to 4 seconds.

There is also a small, deliberately boring cleanup engine built into Megaphone. It removes obvious `um`s, stutters, repeated words, and awkward spacing without asking a language model anything. It powers **Basic Cleanup**, and it is also the safety net when Apple Intelligence is switched off, still downloading, or simply takes too long. So Smart can be clever when it helps, while the deterministic pass makes sure dictation never gets held hostage by cleverness.

## The transcription engine

SpeechAnalyzer is Apple's new speech-to-text API, introduced with macOS 26 and iOS 26. It appears to use the same underlying technology as Apple's system dictation, and it performs remarkably well.

| Engine                            | WER (clean) | WER (noisy) |
| --------------------------------- | ----------: | ----------: |
| **Apple SpeechAnalyzer**          |   **2.12%** |   **4.56%** |
| Whisper Small                     |       3.74% |       7.95% |
| Whisper Base                      |       5.42% |      12.51% |
| Apple SFSpeechRecognizer (legacy) |       9.02% |      16.25% |

<sub>Word error rate on LibriSpeech, measured by [Inscribe](https://get-inscribe.com/blog/apple-speech-api-benchmark.html) on an M2 Pro. Lower is better.</sub>

The accuracy is only part of what makes it useful:

* **It's fast.** SpeechAnalyzer runs much faster than real time on Apple silicon—around three times faster than Whisper Small in Inscribe's testing. Because Megaphone processes audio while you're speaking, there is usually very little left to do afterwards.
* **It's private by default.** Transcription runs on-device. Your recordings are not uploaded to a server.
* **It's free to use.** There is no per-minute API bill. Apple provides the model with the operating system, and each language only needs to be downloaded once.
* **It's a proper native API.** Apple provides an async Swift interface through `SpeechAnalyzer` and `SpeechTranscriber`, including streaming input, partial and final results, contextual vocabulary hints, and automatic model asset management.

As far as I know, Megaphone is one of the first general-purpose dictation apps built entirely around it.

## Privacy

Megaphone does not have a server.

Transcription happens entirely on your Mac, and recorded audio never leaves your computer.

Smart Cleanup also runs on-device through Apple's Foundation Models framework. If Apple Intelligence is disabled, unavailable, or still downloading, Megaphone automatically uses its deterministic Basic cleanup instead. Megaphone exposes no cloud configuration and requires no account or API key.

The two stages have different jobs: SpeechAnalyzer turns audio into words, then Foundation Models tidies those words. The fallback tidier is ordinary code, not a third model. None of the three sends your audio or transcript to Megaphone, because there is nowhere to send it.

## Building from source

```bash
git clone https://github.com/Kuberwastaken/megaphone
cd megaphone
make        # requires Xcode 26 and the macOS 26 SDK
make run
```

## Built with ChatGPT 5.6 and Codex CLI

I built Megaphone for the **OpenAI Build Week hackathon** with **ChatGPT 5.6 and Codex CLI**. In Codex CLI, I used **Sol** with different reasoning effort depending on the task. Lower effort was plenty for copy, UI polish, and straightforward refactors. I used medium effort for features like the Dictionary and wake commands, then higher effort for streaming audio, Swift concurrency, cancellation, updater safety, signing, and bugs spread across a bunch of files.

The setup was really fun. Codex CLI ran on a headless Raspberry Pi and Megaphone ran on my Mac. I would explain what I wanted and what could not break. Codex would inspect the repo, make a change, build or test it on the Mac over SSH, read the failure, and try again. We kept everything in small commits, so it was always easy to see what changed or undo one part.

Subagents were great when the work split naturally. One could dig through updater logs or Apple docs while another worked on the README or a visual. The main agent still had to put it together, run the build, and check the real app. That part mattered. A convincing answer was not enough if the app did not work.

Some things that worked well:

* **Use more reasoning where mistakes are expensive.** A copy change does not need the same attention as an audio cancellation bug or an updater replacing a signed app.
* **Test on the real machine.** Mac builds, codesign output, Accessibility behaviour, updater logs, screenshots, and the live website caught things that looked completely fine in the code.
* **Explain the behaviour you want.** Saying “I want to dictate a sentence, then say ‘Hey Megaphone, make that formal’” led to a much better solution than telling it which variable to add.
* **Keep a boring fallback.** Smart Cleanup still has a deterministic pass. Wake-word aliases have tests for false positives. The website pulls release information from GitHub instead of relying on me to update it every time.
* **Commit small changes.** We changed the app, updater, website, signing, releases, demo media, and docs without ending up with one giant diff nobody could understand.

Codex was most useful because it could keep moving between Swift, shell scripts, GitHub Actions, and the website without losing the thread. I still chose what to build, judged how it felt, recorded the demos, sent screenshots, and decided what shipped. Codex made the gap between an idea and a tested version much shorter. It was also just a lot of fun to build this way.

## Credits

Megaphone is built on top of [**FreeFlow**](https://github.com/zachlatta/freeflow).

A huge thank you to [**Zach Latta**](https://github.com/zachlatta), [@marcbodea](https://github.com/marcbodea), and everyone who has contributed to FreeFlow. The dictation interface, shortcut system, context-aware cleanup, and Edit Mode all started with their work.

If you need a cloud-provider-based dictation app that supports older versions of macOS or Intel Macs, use FreeFlow. It's excellent.

Thanks as well to [Inscribe](https://get-inscribe.com/blog/apple-speech-api-benchmark.html) for publishing the benchmark that made me realise how good Apple's new speech model was.

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">
  Made with &lt;3 and an irresponsible amount of lost sleep by <a href="https://kuber.studio"><b>Kuber Mehta</b></a>
</p>
