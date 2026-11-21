# Step 4: live text and editing lines

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## How live text works (step 4)
- Engine: NVIDIA Parakeet Unified 0.6B (English, punctuation, ~2 s behind
  speech, int8 encoder on the Neural Engine) through FluidAudio 0.18.0
  (`exact:`, `traits: []` so its TTS/diarizer/text-normaliser parts are left
  out). Only `Live/ParakeetEngine.swift` imports FluidAudio.
- Download: ~600 MB to `App Support/Verbatim/Models/Live/parakeet-unified-en-0.6b-coreml`,
  starts on first launch next to the Whisper download, resumes, Pause, auto
  retry every 20 s, then loaded once ("Getting live text ready") and freed.
  Flag `liveModelPrepared` in UserDefaults.
- Backup: Apple SpeechAnalyzer (`Live/AppleSpeechEngine.swift`) when
  Parakeet isn't ready at the moment the mic starts. Its English model is
  requested at launch while Parakeet is missing. Speech Recognition
  permission is asked only then (Info.plist has the text).
- Swappable: `LiveEngine` protocol (`begin` / `feed` / `end`).
- Flow: `AudioPipeline.onSamples` gives every saved sample (Float, 16 kHz)
  to `LiveFeed` (an AsyncStream), `LiveRunner` feeds the engine in order.
  Pause/sleep/disk-full send `.flush` (last words finished, engine reset);
  the engine is picked again when audio comes back, so Parakeet takes over
  from Apple after the next Pause. Times are seconds into audio.wav (the
  runner counts samples), so they line up with Whisper's.
- Memory: Parakeet loaded at the first audio, unloaded after Stop (before
  Whisper starts 10 s later). If no engine can listen, it looks again
  every 15 s of audio.
- Lines: `LineBuilder` joins words; new line after a sentence end (70+
  chars), a pause over 1.6 s, or 260 chars.
- Saved to `Recordings/<id>/live.json` (formatVersion 1) every 10 s and at
  Pause/Stop. Undo Stop keeps adding to it.
- Screen: live lines a little grey; status line on top only when Apple's
  engine or nothing is listening. Auto-scroll only at the bottom, else
  "Jump to live". Copy all works while recording. After Stop, live lines
  the accurate pass hasn't reached show grey under "Checked up to 10:40".
- Step 5 should replace the grey live part with Whisper text as each chunk
  finishes, during recording. It must keep lines with `locked: true`
  (Ryan edited them) and skip text inside `LiveText.removed` spans (lines
  he deleted), or his changes come back.

## Editing lines (pulled forward from step 6, Ryan's ask while testing step 4)
- Click a line (one click, Ryan's ask; was double-click): inline field.
  Text cursor shows over lines. Enter saves, Esc cancels, clicking away
  saves, emptying it deletes. Right-click: Copy this line, Copy from here
  down, Edit line, Delete line, Unlock.
- Works on live and accurate lines, while recording and after.
- Edited lines get `locked: true`, turn full ink, show a lock (click to
  unlock). New live words never go into a line being edited or locked.
- "Line edited. Undo" / "Deleted a line. Undo" in the bottom bar for 10 s.
- Lines are found by their start time (`Model/LineEdits.swift`).
- Transcriber re-reads the lines on screen before adding each piece, so
  edits made while it transcribes are kept. "Transcribe again" still
  throws edits away (explicit action).
- Text in lines is no longer selectable outside edit mode (a click
  would select text instead of editing). Copy this line / Copy from here
  down / edit mode cover copying part of it.

## Step 4 test list for Ryan
1. Start screen: "Downloading live text model" line with %, Pause works.
   Then "Getting live text ready", then "Live text ready".
2. Record yourself reading something aloud: text appears ~2 s behind, in
   grey, with punctuation. Names? (Nyankupon, Anansi, Kweku Tsin)
3. Scroll up while it records: it stops following, "Jump to live" shows.
4. Pause, Resume: last words before Pause show up, carries on fine.
5. Copy all while recording, paste into Claude.
6. Stop: live text stays (grey) until the accurate text replaces it.
7. Activity Monitor > Memory: how much Verbatim uses while recording.
8. If you record before Parakeet finishes: a line says it's using the
   Mac's built-in engine. Does that text look OK?
9. While recording, click a line, fix a word, press Enter: lock
   shows, new words keep coming below. Undo in the bottom bar works.
10. Right-click a line > Delete line, then Undo.
