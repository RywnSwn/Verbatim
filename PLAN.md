# Plan

Status: step 1 done 2026-11-09 (Ryan downloaded v0.1.3 and it opens).
Next: step 2, Record.
Behaviour and edge cases: `docs/spec.md`. Layout to build to:
`docs/design/README.md`.

## Build order (one milestone per chat)

Order is chosen so Ryan can test real accuracy at home early, before any
class depends on it.

0. [x] **Layout design.** Approved mockup in `docs/design/`.
1. [x] **Skeleton + build.** SwiftUI app, GitHub Actions builds a zipped
       .app into GitHub Releases. Ryan downloads and opens it.
2. [ ] **Record.** Record / Pause / Resume / Stop into one crash-safe audio
       file. Sleep prevention, mic picker, level meter, crash recovery.
2b. [ ] **Visual design.** Fonts, colors, spacing on the real SwiftUI app
       (not a web mockup). Ideas: serif for big moments and maybe the
       transcript, system font for controls.
3. [ ] **Transcribe a file.** Drop a Voice Memo, WhisperKit transcribes it,
       model download with resume. Ryan tests accuracy on real classes.
4. [ ] **Live transcript.** Live engine while recording, swappable.
       Test Apple SpeechAnalyzer and NVIDIA Parakeet (the model OpenWhispr
       uses) first.
5. [ ] **Background accurate pass.** Voice detector cuts ~5 min chunks at
       pauses, one job at a time, overlap merge, live text upgrades.
6. [ ] **Transcript tools.** Timestamps, edit + lock, Copy / Copy new,
       export .txt/.md, search.
7. [ ] **Speaker labels.** Teacher vs Student, click to fix.
8. [ ] **Corrections memory.** Word list as Whisper hint, confirmed fix
       rules, Words screen.
9. [ ] **Storage.** History sidebar, 7-day audio delete, Storage screen,
       Recently deleted, Export everything.
10. [ ] **Polish.** First-launch screen, menu bar dropdown, Settings, notifications,
        all the edge cases in `docs/spec.md` that aren't done yet.
11. [ ] **Updates.** In-app update button (Sparkle).

## Nice to have (after the above)
- [ ] Timeline: click a line to hear that bit of audio.
- [ ] Engine comparison screen for live engines.

## Open questions
- Which live engine is good enough (test SpeechAnalyzer vs others).
- Whisper model size that fits 8 GB and is fast enough (test in milestone 3).
- How speaker labels work offline (diarization model choice, milestone 7).
- Is Ryan's Mac a MacBook Air (no fan, slows down when hot) or Pro?
- Should a recording be able to "Keep audio" past 7 days?

## Testing plan
Record a few classes with Voice Memos, run them through the app at home,
keep Claude dictate as backup in class until Verbatim proves itself.
Ask Mr. Yurt before recording class.

## How the build works (step 1)
- `Package.swift`: Swift package, macOS 26, one executable target.
- `scripts/build-app.sh`: `swift build`, wraps the binary in Verbatim.app with
  `Support/Info.plist` (mic permission text), ad-hoc signs, zips. Works with
  only Command Line Tools too.
- `.github/workflows/build.yml`: every push builds on `macos-26` and creates a
  GitHub Release `v0.1.<run number>` with Verbatim.zip. Branch builds are
  marked pre-release; builds from `main` are the normal latest release.
- First open of the unsigned app: double-click, then System Settings >
  Privacy & Security > "Open Anyway" (right-click > Open no longer skips
  the warning on recent macOS).
- No auto update yet: Ryan downloads each new build by hand until step 11.
- No app icon yet (generic icon). Add in the visual design step.
