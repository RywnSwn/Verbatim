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
