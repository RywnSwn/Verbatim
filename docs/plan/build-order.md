# Build order, nice to haves, testing plan

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). All steps 0 to 11 are done; what's next is in `PLAN.md`.

## Build order (one milestone per chat)

Order is chosen so Ryan can test real accuracy at home early, before any
class depends on it.

0. [x] **Layout design.** Approved mockup in `docs/design/`.
1. [x] **Skeleton + build.** SwiftUI app, GitHub Actions builds a zipped
       .app into GitHub Releases. Ryan downloads and opens it.
2. [x] **Record.** Record / Pause / Resume / Stop into one crash-safe audio
       file. Sleep prevention, mic picker, level meter, crash recovery.
2b. [x] **Visual design.** "Notebook" look picked by Ryan and built.
       App icon: done 2026-11-20 (the red Ribbon, see "App icon" below),
       on branch `claude/ux-round-2`, not tested by Ryan yet.
3. [~] **Transcribe a file.** Drop a Voice Memo, WhisperKit transcribes it,
       model download with resume. Ryan tests accuracy on real classes.
4. [x] **Live transcript.** Parakeet Unified (main) + Apple SpeechAnalyzer
       (backup while Parakeet downloads).
5. [x] **Background accurate pass.** Voice detector cuts ~5 min chunks at
       pauses, one job at a time, overlap merge, live text upgrades.
6. [x] **Transcript tools.** Timestamps, (edit + lock done in step 4), Copy / Copy new,
       export .txt/.md, search. Merged, not tested by Ryan yet.
5c. [x] **Drop Whisper, Parakeet only** (Ryan's call, 2026-11-10). See
       "Plan for step 5c" below.
7. [x] **Speaker labels.** Speaker 1, 2..., rename once, click to fix.
       Merged, not tested by Ryan yet (see "How speaker labels work").
7b. [x] **Markers** (Ryan said yes, 2026-11-10). Merged, not tested. ⌘D while recording or
       right-click a line > Add marker here (also after class). Flag next to
       the time. Copy and export put "⚑ " in front of marked lines. "Copy
       marked parts only". Undo in the bottom bar.
7c. [x] **Voice memory** (Ryan's ask, 2026-11-10). Merged, not tested. Remember a voice once
       Ryan names it, so next time "Mr. Yurt" is named by itself. Sortformer
       can enroll saved voice audio (`enrollSpeaker`); check FluidAudio's
       docs on how well it maps. Needs a "Voices" list to rename or forget.
8. [x] **Corrections memory.** Word list via Parakeet vocabulary boosting
       (~100 MB extra download, Ryan said yes), fix rules, Words screen.
       Merged 2026-11-11 (RywnSwn/Verbatim#16) before testing, at Ryan's ask
       (see "How the word list works" and its test list).
9. [x] **Storage.** History sidebar, 7-day audio delete, Storage screen,
       Recently deleted, Export everything. Merged 2026-11-11
       (RywnSwn/Verbatim#17) before testing, at Ryan's ask (see "How storage works").
10. [x] **Polish.** Groups with icons, menu bar, mini window, quiet banners, ⌘K,
        auto names, fuller Settings, text size, battery warning, compact layout.
        Merged 2026-11-12 (RywnSwn/Verbatim#18). Ryan saw it on 0.1.93 to 0.1.99;
        still check: sidebar crash in a small window fixed in 0.1.99?
        (see "How step 10 works" and its test list).
11. [x] **Updates.** In-app update button (own updater, not Sparkle).

## Nice to have (after the above)
- [x] Timeline: click a line's time to hear that bit of audio (clicking the text edits it). Done with the in-app player.
- [ ] Engine comparison screen for live engines.
- [ ] Auto-name recordings from what was said (Ryan's ask), e.g.
      "English: Anansi and the sky god", with Apple's on-device
      Foundation Models (offline, free). Needs Apple Intelligence on.
      Ryan can still rename.

## Testing plan
Record a few classes with Voice Memos, run them through the app at home,
keep Claude dictate as backup in class until Verbatim proves itself.
Ask Mr. Yurt before recording class.
