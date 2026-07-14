<p align="center">
  <img src="Resources/AppIcon-Source.png" width="128" height="128" alt="Megaphone icon">
</p>

<h1 align="center">Megaphone</h1>

<p align="center">
  A free, open-source dictation app for macOS that runs <b>entirely on your Mac</b>,<br>
  powered by Apple's new SpeechAnalyzer engine.
</p>

<p align="center">
  <a href="https://github.com/Kuberwastaken/megaphone/releases/latest/download/Megaphone.dmg"><b>⬇ Download Megaphone.dmg</b></a><br>
  <sub>Requires macOS 26 (Tahoe) on Apple silicon</sub>
</p>

---

Hold `Fn`, speak, and let go. Megaphone types the result into whatever app you're using.

There’s no subscription, no transcription server, and no audio being sent off your Mac.

## Why I built this

I came across [Inscribe's benchmark of Apple's new Speech APIs](https://get-inscribe.com/blog/apple-speech-api-benchmark.html) while scrolling Hacker News yesterday, and the results caught me off guard.

Across 5,559 LibriSpeech utterances, Apple's new **SpeechAnalyzer** reached a **2.12% word error rate**. That beat Whisper Small at 3.74%, Whisper Base at 5.42%, and Apple's older `SFSpeechRecognizer` at 9.02%. It also ran roughly **three times faster than Whisper Small**, completely on-device.

Apple had quietly shipped a genuinely excellent speech model as part of macOS, but very few apps seemed to be using it. Meanwhile, many dictation apps were still charging monthly subscriptions to send recordings to cloud-hosted Whisper APIs.

That felt a little silly, so I built Megaphone.

Megaphone is a fork of the excellent [FreeFlow](https://github.com/zachlatta/freeflow). I removed its cloud transcription stack and rebuilt that part of the app around Apple's SpeechAnalyzer.

## Features

* **Fully on-device transcription** — Apple's speech model processes your audio directly on your Mac. There is no transcription API, API key, or internet connection required.
* **Results as soon as you stop speaking** — Megaphone streams audio into the analyzer while you're talking, so most of the work is already done by the time you release the shortcut.
* **Hold-to-talk or toggle mode** — hold `Fn` to dictate, or press `Command-Fn` to start and stop recording. Both shortcuts can be changed.
* **Edit Mode** — select some text and say what you want changed, such as “make this shorter” or “turn this into bullet points.”
* **Custom vocabulary** — add names, technical terms, and other jargon. Megaphone uses them to guide both Apple's speech model and the optional cleanup step.
* **Multiple languages** — choose any language supported by Apple's on-device model. Megaphone handles the required model downloads from Settings.
* **Plenty of settings** — configure shortcuts, sounds, the recording overlay, clipboard behaviour, voice macros, prompts, and more.

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

## Quick start

1. [Download Megaphone.dmg](https://github.com/Kuberwastaken/megaphone/releases/latest/download/Megaphone.dmg) and drag Megaphone into your Applications folder.
2. Open the app and grant microphone and accessibility permissions.
3. Optionally add a free [Groq](https://groq.com/) API key for AI cleanup and app-context features. This is never used for transcription.
4. Hold `Fn` and start talking. The required Apple speech model will download automatically the first time you use it.

> [!NOTE]
> Releases are not currently notarized by Apple, so macOS may say that it “could not verify Megaphone.dmg is free of malware.”
>
> You can remove the quarantine flag before opening it:
>
> `xattr -d com.apple.quarantine ~/Downloads/Megaphone.dmg`
>
> You can also go to System Settings → Privacy & Security → *Open Anyway*, or avoid the warning by [building the app from source](#building-from-source).

## Privacy

Megaphone does not have a server.

Transcription happens entirely on your Mac, and recorded audio never leaves your computer.

When AI cleanup is enabled, Megaphone sends the text transcript—and, when needed, relevant app context—to whichever LLM provider you configured. You can point it at Ollama, LM Studio, or any other local OpenAI-compatible server to keep those features on-device as well.

## Building from source

```bash
git clone https://github.com/Kuberwastaken/megaphone
cd megaphone
make        # requires Xcode 26 and the macOS 26 SDK
make run
```

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
