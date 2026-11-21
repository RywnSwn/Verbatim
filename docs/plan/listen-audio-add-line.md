# 48 kHz playback audio, Add line below, stereo mic fix (RywnSwn/Verbatim#26)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Next asks (Ryan, 2026-11-19), one chat, branch `claude/listen-audio-add-line`
(built on `claude/protect-data`, so merging it brings item 3 too)
1. Better playback audio. Audio was 16 kHz, squashed to 32 kbps AAC after
   Stop: muffled to listen to. Ryan picked 48 kHz: record a 48 kHz copy for
   listening and shrink it gently after Stop (~45 MB per hour is fine, he
   deletes audio after reviewing). Parakeet keeps getting 16 kHz and the
   transcripts must not change.
2. Add line below. Right-click a line > "Add line below": an empty line to
   type in, time between the lines around it, speaker from the line above
   (click the name to change it), locked like an edit, ⌘Z undoes it.
   Follows the typing rule (one box open, click away saves, no copying).
3. Small: `AudioPipeline` drops the right channel of a stereo mic (no
   downmix), so a 2-mic receiver in split mode loses one mic. Fix.
Not doing: echo removal (could damage his voice in the recording).
Built 2026-11-19, tested by Ryan and merged (RywnSwn/Verbatim#26):
- Audio: `AudioPipeline` takes the mic's own format (no audioSettings) and
  makes two mono files from the same sound with its own converters
  (`downmix = true`, best resampler): audio.wav 16 kHz (Parakeet, speaker
  model, live text, level meter: as before) and listen.wav 48 kHz (only
  for the player, `RecordingStore.playbackURL`). If listen.wav can't be
  written, it's dropped and playback uses the 16 kHz audio. Undo Stop
  carries on listen.wav, padded with silence to stay in step; crash
  recovery repairs it too. `bytesPerHour` counts both while recording
  (~460 MB/h before shrinking).
- `AudioSquash`: audio.wav > audio.m4a 32 kbps (unchanged, ~14 MB/h, what
  Transcribe again reads) and listen.wav > listen.m4a 64 kbps 48 kHz
  (~29 MB/h). Total ~43 MB/h. Delete Audio, old-audio cleanup and the
  size in the sidebar menu use `RecordingStore.audioFiles` (all four).
  Imports and older recordings have no listen copy: they play as before.
- Note: the 16 kHz audio is now made by Verbatim's converter, not macOS's
  (it used to keep only the left channel). Same rate and format for
  Parakeet; a mono mic gives the same sound.
- Add line below (`TranscriptList` `adding`, `RecorderModel.addLine`,
  `newLineTimes`, `LiveTranscriber.discardLine`): right-click a live line.
  The new line is a draft in the view until it has text: empty = nothing
  added. Its own `LineDraft` box and focus; focus loss does not save (the
  name menu may take it), but a click anywhere else, Enter, starting any
  other edit, or leaving the page saves. Esc cancels. The line above is
  covered like other lines. Time: halfway into the gap before the next
  line (just after the last line at the end). Speaker: the line above's
  (`speaker` field, no voice, so changing it never offers to rename a
  whole voice). Locked. ⌘Z / Undo removes it (no "deleted here" mark).
Test list (for Ryan):
1. Record a class bit (or just talk) for a minute, Stop, wait ~20 s, then
   play it: it should sound clearer than before (not muffled). The words
   in the transcript are the same kind of quality as before.
2. Right-click the recording > Delete Audio Only: the size it shows is
   about 43 MB per hour of recording. Undo brings the audio back.
3. If you have the 2-mic receiver: split mode, one mic each side, record:
   both voices are in the recording and in the live text.
4. Right-click a line > Add line below: an empty line opens under it with
   a time and the speaker of the line above. Type, click somewhere else:
   it's added with a lock. Click the name first to change who said it.
5. Add line below, type nothing, click away: nothing is added.
6. Add a line, press ⌘Z: it goes away. While typing in it, ⌘Z undoes typing.
7. While the new line is open, click another line: it only saves, the
   other line does NOT open and does NOT change.
