# History: what was merged when

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). Later status notes are in the files named in `PLAN.md` > Archive.

## Old status notes from the top of PLAN.md (2026-11-09 to 2026-11-10)

Status (2026-11-09, fifth chat): steps 1, 2, 2b, 3, 4, 5, 6 and 11 merged
into `main`. Step 6 merged before testing (Ryan tests through the in-app
update): ask him to run the "Step 6 test list" below. Step 2b merged (Ryan asked to merge before testing; its test
list is below). Step 5 is still not tested
by Ryan: ask him to run the "Step 5 test list" below. Also still
unanswered: line editing on a real Mac, step 3 accuracy on a real class
Voice Memo.
Step 5c (drop Whisper) merged 2026-11-10 (RywnSwn/Verbatim#12) at Ryan's
ask, with the audio shrink after Stop. Not fully tested yet: ask Ryan for
the "Step 5c test list" and the audio shrink test. App icon later.
Step 7 (speaker labels) merged 2026-11-10 (RywnSwn/Verbatim#13) before
testing, at Ryan's ask: ask him for the "Step 7 test list". Step 7b
(markers) built the same day in the same chat (Ryan's ask): see "How markers
work". Step 7c (voice memory) built in the same chat too: see "How voice
memory works". 7b and 7c merged 2026-11-10 (RywnSwn/Verbatim#14, #15) before
testing, at Ryan's ask: ask him for the 7, 7b and 7c test lists. Step 8 (word list) merged 2026-11-11 (RywnSwn/Verbatim#16) before testing, at Ryan's ask: ask him for the "Step 8 test list". Step 9 built in the same chat and merged before testing (RywnSwn/Verbatim#17), at Ryan's ask: ask him for the "Step 9 test list". Step 10 (polish) merged 2026-11-12 (RywnSwn/Verbatim#18) after Ryan approved mockup v3 (https://claude.ai/artifact/2ii2Hd8QkNtZ6gtxUYHziJ): see "How step 10 works" and its test list.
(Another chat had also built 5c, RywnSwn/Verbatim#11; Ryan closed it. Its
branch `claude/step-5c-parakeet-only` couldn't be deleted from the
container; Ryan can delete it on GitHub.)
Fix on 2026-11-10 (sixth chat): Play audio now plays in the app (it opened
Apple Music and was "broken"), plus Delete Audio Only. Ryan: Parakeet is
"pretty good". Not tested by Ryan yet: see "In-app player test list".
Fix on 2026-11-10: accurate pass was dropping sentences (prompt too long,
see step 5 notes). Ask Ryan to record the same kind of lecture again and
compare live vs checked text. Second test (Transcribe again): no more
missing sentences, but doubled lines and made-up text; fixed the same day.
Markers are step 7b (built) and voice memory is step 7c (Ryan, 2026-11-10).

## "Current state" lines moved from CLAUDE.md (2026-11-21)
Where these say `PLAN.md`, the details now live in `docs/plan/` (see the
Archive list in `PLAN.md`).

Steps 1 to 11 merged, plus the in-app player, audio shrink after Stop, the
live text delay fix and the new start screen (2026-11-18, untested by Ryan)
(5c, 6, 7, 7b, 7c, 8, 9, 10 and 2b also not fully tested by Ryan yet).
Line edit fix, ⌘Z undo, page edge, copy times, preloaded live models
(RywnSwn/Verbatim#24) merged 2026-11-19, not tested by Ryan yet.
Code health quick fixes (item 2, RywnSwn/Verbatim#22) and faster start-up
(RywnSwn/Verbatim#23) merged 2026-11-18, not tested by Ryan yet (test lists
in `PLAN.md`). Code health item 3 (protect data, RywnSwn/Verbatim#25), 48 kHz playback
audio, Add line below and the stereo mic fix (RywnSwn/Verbatim#26):
tested by Ryan and merged 2026-11-19. Code health: one item per
chat.
Sidebar never resizes the window, line tools (click picks, double-click
edits, Marker/Note tools, margin mark look) and the ⌘Z-after-delete fix
(RywnSwn/Verbatim#28): tested by Ryan ("all works") and merged 2026-11-20.
UX round 2 (A, B, C, items 2 to 15, update download progress/resume,
Whisper Undo, sidebar overlay fix, pinned sidebar top/bottom rows, sidebar
slide) (RywnSwn/Verbatim#29): merged 2026-11-20 at Ryan's word after he
tried the sidebar; most test lists in `PLAN.md` not run yet.
Code health item 4, speech model errors (restart, say so, redo after Stop,
HitchMeter removed) (RywnSwn/Verbatim#27): merged 2026-11-21 at Ryan's
word, not tested yet. Next code health: item 5 in `PLAN.md`.
Punctuation (2026-11-20): Parakeet already punctuates as well as batch
mode; 2-channel mics now follow the louder mic (merged); Ryan's grammar is
good again on the Mac's own mic, cause unproven (see `PLAN.md`).
Speaker menu ("Who is Speaker 2? (N lines)", numbers never move), line
under the top bar, sidebar learned-width fix (RywnSwn/Verbatim#31, build
0.1.246): merged 2026-11-21 at Ryan's word, test list in `PLAN.md` not
run yet.
Bug hunt 1 (2026-11-21, list in `PLAN.md` "Weekly bug hunts"): bugs 1,
2, 3, 5, 14, 15 fixed (RywnSwn/Verbatim#30), merged 2026-11-21 at Ryan's
word, not tested yet. Next: more hunt 1 bugs (4, 6 to 13, 16).
