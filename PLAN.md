# Plan

Short on purpose, so a new chat reads it fast. All details, old test
lists and "how X works" notes are in `docs/plan/` (list at the end).
When a task finishes, move its notes there and keep this file short.

State (2026-11-21): steps 1 to 11 and every PR up to RywnSwn/Verbatim#31
are merged into `main`. Many are not tested by Ryan yet (list below).

## What's next (in order)
1. Code health item 5, tests: none exist. Add a test target that runs on
   CI (word list fixes, edits kept, speaker naming, WAV writing, old
   recordings). `docs/plan/code-health-review.md`
2. Bug hunt 1, still open: 4 (mixed-up text after a Mac-engine class),
   6 (two Parakeets at once), 7 (delete while a file transcribes),
   8 to 12 (slow spots), 13 (models stay loaded), 16 (download every
   15 s offline). `docs/plan/bug-hunts.md`
3. Code health item 6, cleanup (RecorderModel split, copied code,
   Shortcuts page, Swift 6). `docs/plan/code-health-review.md`
4. PR 21 review leftovers: first words wait for the speaker model, memory
   peak while 3 models load, Undo Stop resets the live text numbers,
   "catching up" should say how far behind, start page date goes stale
   overnight. `docs/plan/code-health-review.md` ("Review of the merged code")
5. App activation re-reads every recording.json.
   `docs/plan/faster-startup.md` ("Not done")
6. Weekly bug hunt (scheduled task, Saturdays 9:38 Myanmar time), last
   hunted commit cd185a5. `docs/plan/bug-hunts.md`

Ideas and asks, not started:
- Mini window still edits a line on one click (big window: click picks,
  double-click edits). `docs/plan/sidebar-and-line-tools.md`
- Cloud Claude can't reach the connector on Ryan's Mac; idea: save
  transcripts to a repo. Not decided. `docs/plan/connector-gear-notes.md`
- Tauri: Claude says stay on Swift, Ryan to decide (`DECISIONS.md`).
- Engine comparison screen for live engines. `docs/plan/build-order.md`
- Dark-mode app icon. `docs/plan/step-02b-look-and-icon.md`
- Step 10 leftovers: "Download again" for models, drag to reorder groups.
  `docs/plan/step-10-polish.md`

## Open bugs from real use
- Live text late (2026-11-18): fixes merged (#21, #24), not confirmed by
  Ryan. If still late, get his ⌃⌘L paste first.
  `docs/plan/bug-live-text-late.md`, `docs/plan/line-edit-undo.md`
- Punctuation gone (2026-11-20): good again, cause not proven. If it comes
  back, get Copy Layout Details right then. `docs/plan/punctuation.md`
- Mini window crash (0.1.150): gone since 0.1.153, trigger never proven.
  `docs/plan/mini-window.md`

## Test lists Ryan has not run yet
Each "Test list" heading is inside the file named, in `docs/plan/`.
- Flag lands on the line above (fixed on main 2026-11-21, build 255):
  flag a few lines with the flag button and the Marker tool, check each
  flag is on the line you picked; old wrong flags should move back too.
- Sidebar cut off at the smallest window (branch
  `claude/fix-squeezed-sidebar`, not merged): `speaker-menu.md`, last part
- Hunt 1 fixes (#30): `bug-hunts.md`
- Speaker menu, top bar line, sidebar width (#31): `speaker-menu.md`
- Speech model errors (#27): `code-health-4-speech-model-errors.md`
- UX round 2 (#29), four lists: `ux-round-2.md`
- Line edit fix, ⌘Z, page edge, copy times, preloaded models (#24):
  `line-edit-undo.md`
- Faster start-up (#23): `faster-startup.md`
- Quick fixes (#22): `code-health-review.md`
- Start screen E, AI Apps, gear menu names (#21): `start-screen-ai-apps.md`
- Connector and notes on lines, mini window, design pass (merged
  2026-11-12): `connector-gear-notes.md`, `mini-window.md`, `design-pass.md`
- Steps 10 (#18), 9 (#17), 8 (#16), 7c (#15), 7b (#14), 7 (#13), 5c (#12):
  the `step-*.md` files
- In-app player and audio shrink: `in-app-player-and-audio-shrink.md`
- Steps 6 and 2b (with the app icon): `step-06-transcript-tools.md`,
  `step-02b-look-and-icon.md`
Tested and done: #25, #26, #28, the louder mic build (v0.1.239).

## Open questions
- Real class: is Parakeet's live text good enough, is the teacher always
  Speaker 1, are quiet students missed?
- Does Apple's backup engine need the Speech Recognition permission?
- Voice memory: can a similar voice get a known name? Word list: does it
  swap real words for names? (`step-07c-voice-memory.md`, `step-08-word-list.md`)
- Only Ryan's Mac can tell: dragging out of Voice Memos, a mic unplugged
  mid-class, and two more (`ux-round-2.md`, end).
- First list (some answered: his Mac is a MacBook Air, Keep Audio exists,
  Whisper is gone): `open-questions-2026-11-09.md`

## CI, smoke test, test builds
Every push builds `v0.1.<run>` on a macOS runner; Ryan's Mac updates to
the highest number, test builds included. The Smoke test runs the app on
the CI Mac and pushes screenshots to `ci-smoke`: look before giving Ryan a
build. Docs-only commits: `[skip ci]`. Details:
`docs/plan/step-01-build-and-ci.md`, `docs/plan/step-11-updates.md`.

## Archive (`docs/plan/`)
- `history.md`: old status notes and CLAUDE.md's merge history
- `build-order.md`: steps 0 to 11 checklist, nice to haves, testing plan
- `step-01-build-and-ci.md`: build, smoke test, branch cleanup, cache
- `step-02-recording.md`, `step-02b-look-and-icon.md`,
  `step-03-transcribe-file.md`, `step-04-live-text.md` (and line editing),
  `step-05-accurate-pass.md` (Whisper, gone), `step-05c-parakeet-only.md`,
  `step-06-transcript-tools.md`, `step-07-speakers.md`,
  `step-07b-markers.md`, `step-07c-voice-memory.md`,
  `step-08-word-list.md`, `step-09-storage.md`, `step-10-polish.md`
  (and its sizing fixes), `step-11-updates.md`: how each step works, with
  its test list
- `in-app-player-and-audio-shrink.md`: player, Delete Audio Only, m4a
- `lag-and-freeze.md`: the 2026-11-12 lag hunt and freeze cause
- `mini-window.md`: redesign, mockup, crash fix
- `design-pass.md`: sidebar rows, drag, glass/solid, Settings pages
- `connector-gear-notes.md`: Claude connector (MCP), gear menu, notes
- `start-screen-ai-apps.md`: start screen E, AI Apps (#21)
- `bug-live-text-late.md`: live text late in class
- `code-health-review.md`: the 7 items, quick fixes, PR 21 review
- `faster-startup.md`, `code-health-3-protect-data.md`,
  `code-health-4-speech-model-errors.md`: code health items 7, 3, 4
- `line-edit-undo.md`: LineDraft fix, TypingShield, ⌘Z, preloaded models
- `listen-audio-add-line.md`: 48 kHz audio, Add line below, stereo mic
- `sidebar-and-line-tools.md`: sidebar buttons, overlay sidebar, line
  tools, UX check round 1
- `ux-round-2.md`: A, B, C lists and how they were built
- `punctuation.md`: punctuation tests, louder mic
- `speaker-menu.md`: "Who is Speaker 2?", top bar line, sidebar width
- `bug-hunts.md`: weekly hunts, hunt 1 list
- `open-questions-2026-11-09.md`: the first open questions
