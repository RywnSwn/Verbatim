# Decisions (and why)

All from the planning chat on 2026-11-09 unless dated otherwise.

## Why this app exists
Ryan used Claude's dictation mic in class. It cut off between fragments,
had no speaker labels, and misheard names (Nyankupon became "group bonds",
Anansi became "Father Nazi"). Off-the-shelf options were each missing
something (Apple Notes: no speakers, so-so accuracy; noScribe: not live).

## Two passes: live + accurate
Whisper works on ~30 s chunks and is not built for live, so live apps fake
it by re-running on the last few seconds. Live text is rough. A background
Whisper pass fixes it. Ryan rarely reviews after class, so the live side is
the main use, and the accurate pass should run DURING class.

## Fixed chunks, not "half the elapsed time"
Ryan's first idea was to re-pass half the elapsed time every 5 min. He
spotted the flaw himself: jobs grow (20 min of audio at minute 40) and can
overlap and collide. Chosen: each pass handles only new audio since the
last pass plus a few seconds of overlap, one job at a time in a queue.

## Cutting chunks safely
Cut at a pause near the 5-min mark using a voice activity detector (our
code, not Whisper), keep overlap and merge, and pass the previous chunk's
text plus the word list as Whisper's initial prompt for context.

## Live engine is swappable
Ryan has heard Apple's built-in dictation is not that good. Candidates to
test (check current state first): Apple's speech API, Moonshine, NVIDIA
Parakeet, Kyutai STT, Vosk. WhisperKit also supports streaming.

## Stack
- Considered Rust + Tauri, Rust + GPUI, Swift + SwiftUI.
- Tauri: rejected by Ryan (web view feel). Electron: never.
- GPUI: thin docs, API churn, most back-and-forth.
- Swift + SwiftUI + WhisperKit: leaning choice. Native Apple feel (what
  Ryan wants), lots of examples, WhisperKit is optimized for Apple Silicon.
  Ryan dislikes Swift but Claude writes all the code, so he never touches it.

## Building without Xcode
Ryan won't install Xcode. Options: GitHub Actions macOS runner (repo is
public so minutes are free; private repos burn macOS minutes ~10x), or
Command Line Tools + `swift build` on his Mac. The .app bundle,
Info.plist (mic permission text) and ad-hoc signing are done by a script.
Unsigned app: first open is right-click > Open.

## Downloads
App is small and re-downloaded per update. The Whisper model downloads once
on first launch and is cached separately, so updates don't re-download it.

## No Windows version
SwiftUI is Mac only, so a Windows build would be a second app. Test with
recorded audio instead.

## Privacy
Audio kept 7 days max. Everything runs locally on the Mac, no cloud.

## Stack confirmed (2026-11-09)
Ryan said yes to Swift + SwiftUI + WhisperKit.

## Minimum macOS 26 (2026-11-09)
Ryan is on Tahoe 26.7 and asked for it to keep working on a future Mac.
Apps built for macOS 26 also run on later versions, so no rewrite for a
new Mac. Data lives in Application Support (Migration Assistant moves it),
and saved files carry a format version for safe upgrades. Targeting 26
also unlocks Apple's newer SpeechAnalyzer API, which is a different and
better engine than the old dictation Ryan heard was weak, so it is the
first live engine to test. It runs outside our app's memory, which helps
with 8 GB.

## Build order: file transcription before live (2026-11-09)
"Transcribe a file" comes before live transcription so Ryan can test
accuracy on real Voice Memos at home early.

## Keep the app small (2026-11-09)
No themes, accounts, cloud, summaries or in-app AI chat. Undo instead of
confirm popups (only exception: quitting while recording). Full list of
small behaviours in `docs/spec.md`.

## Layout approved (2026-11-09)
Mockup in `docs/design/`. Design first so later chats build to a written
layout instead of drifting. Ryan's calls: no red recording UI, mono waveform
as the signature, no soft bordered boxes, messages in the status spot instead
of popups or banners, menu bar dropdown instead of a mini window (Ryan rated
the mini window poorly), MacBook mic default (AirPods mics not trusted),
editorial serif only for big moments. Features added because Ryan would use
them in class: copy options (new / last 10 min / marked), markers, right-click
line menu ("copy from here down"), a few shortcuts. Cut as decoration: stats
inspector, timeline waveform.

## OpenWhispr (2026-11-09)
Ryan asked about it. It's an Electron dictation app (wrong job, wrong stack),
but its models (Whisper, NVIDIA Parakeet) are separate and free. Parakeet is
a live engine candidate.

## How Ryan gets builds (2026-11-09)
Every push builds on GitHub's macos-26 runner and publishes a GitHub Release
with Verbatim.zip, so Ryan just downloads from the Releases page. Branch
builds are pre-releases so he can test before anything is merged. Apple
Silicon only (arm64), ad-hoc signed, no paid Apple developer account.

## Step 3 choices (2026-11-09)
- Model: Whisper large-v3 turbo compressed (626 MB), Argmax's
  recommendation for accuracy, fits 8 GB. Swap if too slow on Ryan's M2.
- Our own ~2 min pieces cut at quiet points instead of one big WhisperKit
  call: text appears as it goes, Cancel/resume work, and step 5 reuses it.
- Transcribe automatically after Stop (Ryan rarely reviews, wants text
  without extra clicks).
- Delete moves to the macOS Trash with Undo (added early because Ryan
  needed it; in-app Recently deleted still in step 9).
- Visual design (2b) moved after step 3 so it polishes more real screens.

## Updates pulled forward, own updater instead of Sparkle (2026-11-09)
Ryan found download + unzip + Open Anyway + mic prompt on every build
annoying, so step 11 moved before step 4. Own small updater on GitHub
Releases instead of Sparkle: no appcast or EdDSA key to manage, and the
update is checked by code signature against a stable self-signed
certificate (which also stops the mic prompt after every update).

## Live engine: Parakeet first, Apple as backup (2026-11-09)
The plan said to test Apple's SpeechAnalyzer first. Ryan wanted a good
downloaded model instead. Chosen: NVIDIA Parakeet Unified 0.6B via
FluidAudio, a true streaming model (~2 s behind speech, punctuation,
~2.2% WER on LibriSpeech), not the sliding-window TDT mode (11+ s behind).
It runs on the Neural Engine, which Whisper mostly doesn't use. Apple's
engine fills in only while Parakeet is still downloading, so the first
recording still gets live text and costs no extra memory. Options Ryan
didn't pick: Parakeet only, or a Settings switch to compare both.

## Step 5 choices (2026-11-09)
- Cut chunks between live lines (they already break at pauses), so a live
  line is never half checked. Energy based quiet point as fallback.
- Merge seams word by word (Whisper word timestamps) with 1 s overlap,
  instead of segment level, so words aren't doubled or dropped.
- Whisper is loaded only while a chunk is being checked, then freed (8 GB
  Mac). Costs a few seconds per chunk, saves ~1 GB most of the class.
- The recording in progress goes before imported files in the queue.

## Visual design: "Notebook" (2026-11-09)
Ryan picked look A from three (Notebook, Plain Mac, Graphite): New York
serif transcript at 17 pt, warm white paper, ink text, system font for
controls. He questioned the blue Copy all, so the main button is ink
(matching the mono waveform); bright Mac blue is gone, links use a dark
ink blue. Sidebar and Settings stay standard Mac so the app still feels
native. Auto-naming recordings with on-device AI added to nice-to-haves.

## Whisper prompt kept tiny (2026-11-10)
Ryan's first real lecture test: the accurate text was missing whole
sentences and read worse than live. Cause: WhisperKit's decoder context is
224 tokens per 30 s window and our 120 token prompt left too little room,
so windows got cut off and skipped. Prompt is now 32 tokens. Live lines
Whisper clearly skipped are kept, so the accurate pass can't lose text.

## Drop Whisper, Parakeet only (2026-11-10)
Ryan, after two lecture tests: "lets just ditch whisper, Parakeet is really
good". Whisper's accurate pass skipped, doubled and invented text; fixes
(smaller prompt, clean-up against live text) helped but it still read
worse than live. Parakeet Unified's streaming WER is within 0.05 points of
its own batch mode, and it doesn't hallucinate. One model also means one
download and less memory on the 8 GB Mac. Replaces "Two passes: live +
accurate" and the step 5 choices. Plan: `PLAN.md`, step 5c.

## Step 5c choices (2026-11-10)
- A file job (import, "Transcribe again") waits while a recording is going,
  instead of loading a second Parakeet. Simpler, and the 8 GB Mac only ever
  holds one copy of the model. A running job stops at the end of its current
  30 s piece of audio (well under a second) and carries on after Stop.
- Files use the same streaming Parakeet as live text, fed at full speed. No
  new download. The batch mode is a bit more accurate but needs an extra
  encoder; only worth it if Ryan finds files worse than live.
- Recordings made with Apple's backup engine get a Parakeet pass by
  themselves after Stop (no button to press). Ryan's edits and deletions
  in the live text are kept in that pass and in "Transcribe again".
  If Parakeet wasn't downloaded yet at Stop, the transcript offers
  "Redo with Parakeet" later.
- Each line saves when every word starts (`Transcript.Line.words`), so the
  in-app player marks the exact word being heard. Edited lines lose them
  and the player estimates.
- Two chats built step 5c at the same time. Ryan kept the one built on top
  of the in-app player (`claude/step-5c-mine`) and closed the other
  (RywnSwn/Verbatim#11); its docs and "keep edits" idea were copied over.
- The old Whisper model (626 MB) is deleted on launch so Ryan gets the
  space back. Old Whisper transcripts still open.

## Speaker labels: Sortformer, "Speaker 1, 2..." (2026-11-10, step 7)
- Sortformer (FluidAudio) over LS-EEND and pyannote: best in noise, very
  stable voices, works live. 6-bit "balanced" model: ~100 MB, low memory on
  the 8 GB Mac. Its weak spot is quiet, far-away speech (students at the
  back may be missed); Ryan tests that in class.
- First built as "most words = Mr. Yurt, everyone else = Student" with
  names in Settings. Ryan said no the same day: he uses Verbatim for
  videos and anything, not only that class. So voices are "Speaker 1"
  (talks most), "Speaker 2"..., renamed in the transcript, and typed names
  are offered in every recording. No speaker settings.
- Recordings without speakers (old ones) get them by themselves once the
  model is downloaded, without changing the text.
