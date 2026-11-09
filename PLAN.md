# Plan

Status: planning finished 2026-11-09, nothing built yet. Stack confirmed.
Detailed behaviour and edge cases: `docs/spec.md`.

## Build order (one milestone per chat)

Order is chosen so Ryan can test real accuracy at home early, before any
class depends on it.

1. [ ] **Skeleton + build.** SwiftUI app, GitHub Actions builds a zipped
       .app into GitHub Releases. Ryan downloads and opens it.
2. [ ] **Record.** Record / Pause / Resume / Stop into one crash-safe audio
       file. Sleep prevention, mic picker, level meter, crash recovery.
3. [ ] **Transcribe a file.** Drop a Voice Memo, WhisperKit transcribes it,
       model download with resume. Ryan tests accuracy on real classes.
4. [ ] **Live transcript.** Live engine while recording (Apple
       SpeechAnalyzer first, swappable).
5. [ ] **Background accurate pass.** Voice detector cuts ~5 min chunks at
       pauses, one job at a time, overlap merge, live text upgrades.
6. [ ] **Transcript tools.** Timestamps, edit + lock, Copy / Copy new,
       export .txt/.md, search.
7. [ ] **Speaker labels.** Teacher vs Student, click to fix.
8. [ ] **Corrections memory.** Word list as Whisper hint, confirmed fix
       rules, Words screen.
9. [ ] **Storage.** History sidebar, 7-day audio delete, Storage screen,
       Recently deleted, Export everything.
10. [ ] **Polish.** Onboarding, menu bar icon, Settings, notifications,
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
- Clock time or time-since-start as the default timestamp?
- Should a recording be able to "Keep audio" past 7 days?
- GitHub's macOS 26 runner: check it exists and builds the app.

## Testing plan
Record a few classes with Voice Memos, run them through the app at home,
keep Claude dictate as backup in class until Verbatim proves itself.
Ask Mr. Yurt before recording class.
