# Line edit fix, ⌘Z, page edge, copy times, preloaded live models (2026-11-19, RywnSwn/Verbatim#24)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Line edit fix, ⌘Z, thinner rule (2026-11-19, branch `claude/fix-line-edit-undo`)
Ryan's report: while editing a line, clicking another line copied the
edited text into that line and replaced it. Also asked for a "hitbox" over
the page while editing (mini window too), an undo feature, and said the
rule under the title was thick with the spacing off.
- Cause of the copy bug: one shared `LineDraft` box for all edits. The old
  TextField writes its text one last time as it closes, after `begin` had
  put the new line's text in the box, so the new line got the old text.
  Fix: `begin` (TranscriptList, MiniLines) and `beginNote` make a new box.
- `TypingShield` (TranscriptList.swift): while a line or note is typed,
  every other line, the header, the gaps and margins are covered; a click
  only saves. Right-click on other lines is covered too (click once first).
  Mini window: other lines just save (`MiniLineRow.covered`).
- Undo: `offerLineUndo` now pushes onto `undoStack` (last 50, until quit).
  Edit > Undo ⌘Z (`RecorderModel.undo`): in a text box it undoes typing,
  else a deleted recording/audio still showing Undo, else the newest change.
  Flashes "Undid: line edited." Redo only works for typing.
- Rule: 1 pt in `Theme.rule` (was 1.5 pt full ink). Start page now has the
  same space as a transcript header: 14 above, 24 to the first line; the
  hint sits above the model status so an empty status adds no gap.
Test list (for Ryan):
1. Click a line, change it, click a different line: the first line saves,
   the second is NOT changed and does not open. Click it again to edit it.
2. Same in the mini window while recording.
3. Edit 3 lines, then press ⌘Z three times: each goes back, newest first.
   While typing in a line, ⌘Z undoes typing only.
4. Start page: the line under the title is thin and the gap above and
   below looks even. Press Record: title, line and text don't jump.
Same day, Ryan: the gap between the sidebar and the title was too big.
The start page and every transcript header (title, details, rule) and
the "Listening" hint now start at the page edge (32 pt from the sidebar),
not 70 pt in past the time gutter. Transcript lines keep the gutter: the
times sit under the title's left edge. Test: start page title is close to
the sidebar; open a class: its title starts at the same spot; press Record:
nothing moves sideways.
Same day, Ryan: copies and exports had no time or speaker, and the time
in the gutter wrapped ("10:42 A" / "M").
- Times in copies (Settings > General) now default ON
  (`TimeStyle.includeInCopies`); it was off by default.
- Speakers: the code already writes `[Mr. Yurt]: "text"`. The smoke test
  now presses Copy All and fails if "Mr. Yurt" is missing (copy-all.txt in
  `ci-smoke`). If it passes there but Ryan still sees none, ask how he
  copies and which recording (a Voice Memo before speakers were found?).
- Gutter: 60 pt + 10 pt gap (was 52 + 18, same 70 total), one line always.
Same day, Ryan: live text takes a few seconds after Record, and after an
early Stop (30 s, no words yet) the page showed a big "Transcribe" screen.
- Cause: every Record loaded Parakeet (+ word spotter) and the speaker
  model from disk first; they're unloaded at Stop to free memory.
- `LiveTranscriber.warmUp()` / `LiveRunner.warm()`: the start page loads
  them while it's open (StartView .onAppear, when the model gets ready, and
  after the Transcriber's queue empties if the start page is showing).
  Runs in the same chain as recordings (`runTask`), so Record mid-load just
  waits. Not while recording or while a file is transcribed. The
  Transcriber calls `coolDown()` before its own Parakeet loads (8 GB: one
  at a time). Known voices are still played to the speaker model at Start.
- No more `emptyState` screen in PastRecordingView: always the transcript
  page, with a hint where the first line goes: "Finishing the text…" while
  the live run is still on that recording, "No text yet. Transcribe" (link)
  when nothing is working on it, else as before.
Test: open the app, wait 10 s on the start page, press Record and talk:
words should come within ~2 s. Stop after 10 s: same page, words fill in.
If still slow, paste ⌃⌘L ("LIVE TEXT START" line).
