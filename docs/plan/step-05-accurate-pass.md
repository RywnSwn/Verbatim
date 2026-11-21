# Step 5: background accurate pass (Whisper, removed in step 5c)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## How the background accurate pass works (step 5)
- `Transcriber.growing`: recordings still getting audio (recording, paused,
  or in the 10 s Undo Stop window). `RecorderModel` calls
  `recordingStarted` (start, Undo Stop), `audioGrew` (every 10 s) and
  `recordingFinal` (when Undo Stop expires; replaces the old enqueue).
- A chunk starts once there are 5 min + 15 s of unchecked audio
  (`chunkSeconds`, `settleSeconds`). The 15 s lets live text for that bit
  become final.
- Cut: the longest gap between live lines in the 30 s before the 5 min
  mark, at its quietest 0.1 s, so live lines are never split. No live text:
  quietest moment in the 20 s before the mark (`WavReader.quietPoint`).
- Overlap: each piece starts 1 s before the cut. Whisper runs with word
  timestamps; `Transcribe/ChunkMerge.swift` drops words whose middle is
  before the cut, inside a deleted live line (`LiveText.removed`) or inside
  a locked live line, then adds the locked live lines as they are. A line
  belongs to the side of the cut its middle is on (`Line.middle`,
  `LiveText.unchecked(after:)`).
- Prompt: the last 3 checked lines (max 150 chars, 32 tokens) go to
  Whisper as context. Was 120 tokens: WhisperKit's decoder holds only 224
  tokens per 30 s window including the prompt, so fast speech got cut off
  and the rest of the window skipped (Ryan's first real test, a history
  lecture: whole sentences missing, accurate text worse than live). Step 8's
  word list must fit in this small budget too.
- Clean-up (`ChunkMerge.cleaned`, `TextCheck`, compares word pairs): drops
  Whisper segments that loop ("I'm not a vampire" x8), the start of a
  segment that repeats the end of the one before, segments that mostly
  repeat the two before, and segments with almost nothing in common with
  the live text around them (made up). Then a live line whose word pairs
  are mostly missing from Whisper's text within 20 s is kept as it is
  (`ChunkMerge.skipped`). By text, not time: the first version compared
  times and doubled lines in Ryan's second test. Segments that just repeat the prompt are dropped.
  Step 8 adds the word list in `Transcriber.promptText`.
- While Ryan edits a live line inside the chunk, the merge waits until he
  is done. Undo of a live edit/delete after the line got upgraded applies
  to the checked text (`LineEdits.restore`).
- The recording in progress jumps ahead of imports: a file job yields after
  its current piece when a recording chunk is ready.
- Memory: Whisper loads for each chunk and unloads after (queue empty), so
  during class it is in memory only while checking. Parakeet stays loaded.
- Low Power Mode: chunks wait, bottom bar says so, and everything catches
  up after Stop (spec). Turning it off starts a waiting chunk.
- Screen: recording view shows checked text, the "Checked up to" divider,
  then grey live text. Bottom bar status spot: "Checking 10:40 to 10:45".
- Post-stop and imported files use the same code (2 min pieces, overlap,
  word merge).
- Not done: "falling behind" message, Settings choice for the 5 min
  (both step 10). Possible screen jump when a chunk lands while scrolled up:
  ask Ryan.

## Step 5 test list for Ryan
1. Record 12+ min (a video or podcast is fine). Around 5:15 the bottom
   right says "Checking ..." for a bit, then the top part turns from grey
   to black with "Checked up to ..." under it. Again around 10:30.
2. Read the seam around the 5 min mark: any doubled or missing words?
3. While recording, delete a grey line and edit another one before they
   get checked. After the check: deleted stays gone, edited stays as you
   wrote it with the lock.
4. Scroll up while a check lands: does the screen jump?
5. Stop: the last few minutes get checked within a minute or so.
6. Activity Monitor: memory while "Checking" shows vs between checks.
7. Turn on Low Power Mode while recording: bottom right says checking
   waits. Stop: it catches up.
8. Import a Voice Memo, then start recording: the recording's checks still
   happen during the import.
