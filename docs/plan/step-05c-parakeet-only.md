# Step 5c: drop Whisper, Parakeet only

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Plan for step 5c: drop Whisper (built, see "How step 5c works")
Why: in Ryan's two lecture tests Whisper skipped sentences, doubled lines
and made text up ("I'm not a vampire" x15), even after fixes. Parakeet's
live text was better. FluidAudio's own benchmark (LibriSpeech test-clean):
Parakeet Unified streaming 2.21% avg WER, batch 2.16%, so the live text is
already about as accurate as it gets, and RNNT can't invent sentences.
What to build:
- Recordings: the live text IS the transcript. No checking pass, no
  "Checked up to" divider, no "Checking 10:40 to 10:45", live lines full
  ink once final (half-said words can stay lighter). Edits/locks/deletes
  keep working as they do on live lines.
- Imports and "Transcribe again": run Parakeet over the WAV (feed the
  existing streaming engine at full speed, ~66x real time per FluidAudio,
  so a 1 h class in about a minute). Same model, no new download. Decide
  whether an import waits while recording (one model in memory, 8 GB Mac)
  or uses a second instance; waiting is simpler.
- Recordings made with Apple's backup engine (Parakeet wasn't ready):
  offer/auto "Transcribe again" with Parakeet after Stop.
- Remove WhisperKit (Package.swift), `WhisperEngine.swift`, the Whisper
  download/prepare lines on the start screen, `ChunkMerge` / `TextCheck`
  and the 5 min chunk logic in `Transcriber`. Keep the queue idea for files.
- On launch, delete the old Whisper model folder (626 MB) in
  App Support/Verbatim/Models once, so Ryan gets the space back.
- Old recordings with a Whisper transcript.json still open and show it.
- Step 8 changes: no Whisper prompt any more. Ryan wants the extra
  download for names (2026-11-10): FluidAudio vocabulary boosting. Checked
  in FluidAudio 0.18.0: `StreamingUnifiedAsrManager.configureVocabularyBoosting`
  (works live, not only on files) with `CustomVocabularyContext` + a
  separate Parakeet CTC 110M model (`Repo.parakeetCtc110m`, ~97.5 MB
  download, ~64 MB extra memory). See FluidAudio
  `Documentation/ASR/CustomVocabulary.md`. Plus find/replace fix rules for
  anything it still misses. Words screen as planned.
- Spec and design docs: remove "accurate pass" parts.
- Save real word times (Parakeet gives token timings) on each line, e.g.
  `Transcript.Line.words: [start]` or similar, dropped when Ryan edits the
  line. The player's word highlight (`TranscriptList.wordHighlighted`)
  estimates by word length today; switch it to real times when present.
- Optional later: FluidAudio's `UnifiedAsrManager` (batch, full-attention
  15 s encoder, same checkpoint) is a bit more accurate for files but needs
  an extra encoder download. Not worth it unless Ryan finds files worse.
Test list for Ryan: record a lecture video, text is final right away and
stays the same after Stop; import a Voice Memo, done in about a minute;
Settings/start screen no longer mention a second model; disk space back.

## How step 5c works (Parakeet only)
- `live.json` (`LiveText`) is the transcript. Recordings made with Parakeet
  need nothing after Stop. All lines full ink; only Apple's half-said words
  are lighter.
- `Transcribe/Transcriber.swift` (rewritten): a queue of files. Each job
  feeds the WAV to its own `ParakeetEngine` in 30 s pieces at full speed,
  adding words to live.json through `LiveTranscriber.addPass`. Progress in
  `LiveText.pass` (`doneUpTo`, `finished`, `stoppedByUser`), saved after
  every piece; after a crash it carries on from the last word saved.
- Files wait while a recording is going (`growing`): a running job flushes
  its words and stops at the end of its piece, then carries on after the
  recording is final (Undo Stop expired). Status line: "Waits until you
  stop recording".
- Used for: imports, "Transcribe again", recordings with no live text, and
  recordings made with Apple's backup engine (redone by themselves after
  Stop if Parakeet is ready; otherwise "Redo with Parakeet" link).
- "Transcribe again" keeps edits: locked lines go into `pass.keep` and are
  put back in place as the pass gets there (Parakeet's words inside them
  are dropped); `removed` spans stay removed.
- Word times: `Transcript.Line.words` = start of each word (0.01 s), made
  by `LineBuilder`. The player uses them; edits clear them.
- Old recordings: a Whisper `transcript.json` still shows (as "checked"
  lines, then live lines after its end under "Old transcript ends at").
  An unfinished one with no live text gets "Continue", which runs
  Parakeet from where Whisper stopped.
- Whisper model folder: everything in App Support/Verbatim/Models except
  `Live` is deleted once on launch (`whisperModelRemoved` flag).
- Start screen: one "speech model" line (was two).

## Step 5c test list for Ryan
1. After updating: start screen shows one "Speech model ready" line, no
   "accurate model". Finder > App Support/Verbatim/Models: only `Live` left.
2. Record a few minutes (a lecture video is fine): text is black right
   away, no "Checked up to", nothing changes after Stop.
3. Drop a Voice Memo: "Transcribing ... min left", done in about a minute
   per hour of audio. Cancel halfway, then Continue.
4. Import a file, then start recording before it finishes: the file says
   it waits, then finishes after you stop.
5. Play audio on a new recording: the blue mark sits on the exact word.
6. Edit a line, then More > Transcribe again: your edit is still there.
7. Old recordings still open and look the same.
