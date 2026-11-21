# Faster start-up (code health item 7, 2026-11-18, RywnSwn/Verbatim#23)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Faster start-up: DONE 2026-11-18 (branch `claude/faster-startup`)
Measured with the smoke test: 200 old classes with ~330 KB live.json each
(about 66 MB of text) in a folded group, plus the usual 3.
Seconds after the app started (first launch / second launch):
- Before (4a18d3c): saved classes read 2.24 / 2.01 (2.12 / 1.98 of it
  with the main thread blocked), window shown 3.86 / 2.81.
- After (e1191bd): saved classes read 0.35 / 0.41 (0.27 / 0.36 blocked),
  window shown 1.42 / 2.01. First launch read the 201 texts in the
  background, done at 2.62 s. Second launch had nothing to check.
- What's left on the main thread (~0.3 s) is reading the 203
  recording.json files.
The answers Claude gets (MCP) were the same before and after.
How it works now:
- `Live/TextIndex.swift`: `text-index.json` (next to the Recordings
  folder) keeps `TextFacts` per recording (has lines, file pass finished
  or not, stopped by Ryan, speakers found, has voices, backup engine) plus
  the size and date of the live.json they came from.
- `LiveTranscriber.start(with:)` reads that one file and checks each
  live.json's size and date. Entries that don't match (first launch after
  this update, a quit between saves, Put Back, an older Verbatim) are read
  off the main thread one at a time (`checkInBackground`), then
  `Transcriber.textChecked(id)` picks up unfinished work for that one.
- `texts[id]` reads the live.json the first time something asks for it
  (opening, copying, exporting, finding speakers, MCP). Old Whisper
  transcripts (`Transcriber.transcripts[id]`) the same way.
- `facts(id)`: nil = still being checked. Old audio cleanup skips those.
- The index is saved 2 s after a change and at quit.
- recording.json files are read once at launch, not twice.
- `Model/LaunchTimer.swift`: "LAUNCH: ..." lines in the log and in ⌃⌘L
  (seconds after the app process started).
Faster start-up test list (for Ryan):
1. First launch after the update: the app opens, and within a few seconds
   everything looks as before (old classes, their names, checked text).
2. Open an old class: its text shows right away. Copy it, export it: same.
3. Quit and open again: should open a bit faster. Press ⌃⌘L and paste the
   "LAUNCH" line to Claude.
4. Record a short class, Stop, quit within a few seconds, open again:
   the class and its text are all there.
Not done (found here, for later):
- Every time the app becomes active (`didBecomeActive`), `reload()` reads
  every recording.json again on the main thread. Small now, grows with a
  year of classes. Only reload when something changed.
- While recording, the whole live text is encoded and saved every 10 s on
  the main thread. A long class could make that a small hitch. Save off
  the main thread (fits item 3, protect data).
