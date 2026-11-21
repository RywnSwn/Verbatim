# Step 2: recording

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## How recording works (step 2)
- Audio: `AVCaptureSession` on the chosen mic, converted to 16 kHz mono
  Int16 (what Whisper wants), ~115 MB per hour. `Audio/AudioPipeline.swift`.
- File: `~/Library/Application Support/Verbatim/Recordings/<id>/audio.wav`
  plus `recording.json` (formatVersion 1, events with sample positions for
  pause, sleep, mic change, undo stop, recovered). `Audio/WavWriter.swift`
  syncs the header every 2 s; on launch, recordings still marked recording
  get their header repaired and a notice line shows.
- Pause stops the mic (orange dot goes off), same file. Undo Stop (10 s)
  reopens the file and appends.
- Sleep: system idle sleep blocked while recording. Lid close: mic stops
  on sleep, restarts on wake, status says "Mac was asleep X to Y".
- Mic: default MacBook mic (`Microphones.swift`); Settings > General picks
  another; unplugged falls back to the MacBook mic and says so.
- Delete: right-click > Move to Trash or Cmd+Delete moves the folder to the
  macOS Trash, with Undo for 10 s. In-app Recently deleted is still step 9.
- Not yet: menu bar
  dropdown (step 10), teacher name in subtitle, recording title is always
  "English" (rename from the sidebar right-click menu).
- Ad-hoc signing changes every build, so macOS may ask for mic permission
  again after each update. Fix later with a stable signing identity.

## Step 2 test list for Ryan
1. Start, talk, watch the waveform move. Pause: dots, "Paused". Resume.
2. Stop, then Undo Stop within 10 s: timer continues.
3. Play audio from the sidebar: clear, nothing missing around the pause.
4. Record for a minute, force quit (Cmd+Option+Esc), reopen: notice line,
   audio is there.
5. Cmd+Q while recording: asks first.
6. Settings (Cmd+,): pick AirPods, see the warning, switch back.
7. Record 30+ min untouched: Mac doesn't sleep.
