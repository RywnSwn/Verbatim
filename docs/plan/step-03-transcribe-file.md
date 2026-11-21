# Step 3: transcribe a file (Whisper era, replaced by step 5c)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## How transcription works (step 3)
- WhisperKit 1.1.1 from `argmax-oss-swift`, model
  `large-v3-v20240930_626MB`, stored in
  `~/Library/Application Support/Verbatim/Models` (outside the app, so
  updates don't re-download). Only `Transcribe/WhisperEngine.swift` imports
  WhisperKit.
- Download starts on first launch; WhisperKit's downloader resumes partial
  files. Our side: progress, time left, Pause, auto retry every 20 s.
  After download the model is loaded once ("Getting the model ready") to
  fetch the tokenizer while online and let macOS optimise it.
- `Transcribe/Transcriber.swift`: queue, one job at a time, model unloaded
  when idle. Each job cuts the WAV into ~2 min pieces at the quietest
  0.1 s near the cut, transcribes, shifts times, saves `transcript.json`
  after every piece (so text appears as it goes; Cancel and crashes keep
  progress; Continue resumes). Junk phrases ("Thanks for watching") dropped.
  Step 5 should reuse this piece logic.
- Recordings are queued 10 s after Stop (when Undo Stop expires). On launch,
  unfinished ones are re-queued unless Ryan pressed Cancel.
- Import: drop a file on the window or Cmd+O. `AudioImport` converts it
  to our WAV with AVAssetReader, original untouched. Imports show time
  since start in the gutter, recordings show clock time (pauses skipped).
- Transcript view: status line on top, time gutter, Copy all (Shift+Cmd+C,
  plain text, no speakers yet), More menu (Play audio, Show in Finder,
  Transcribe again, Move to Trash).

## Step 3 test list for Ryan
1. First launch: model download line on the start screen, Pause/Resume.
2. After download: "Getting the model ready", then "ready".
3. Old recordings get text by themselves. Text appears piece by piece.
4. Drop a real class Voice Memo: accuracy? names? how long did it take?
5. Copy all, paste into Claude.
6. Cancel halfway, then Continue.
