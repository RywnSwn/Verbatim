# Speech model errors (code health item 4, RywnSwn/Verbatim#27)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Speech model errors (code health item 4, 2026-11-19)
RywnSwn/Verbatim#27, merged 2026-11-21 at Ryan's word, not tested by Ryan.
How it works:
- `LiveEngine.feed` now `throws`. Parakeet passes FluidAudio's error on
  (it used to return no words and the app kept saying "listening").
  Apple's engine remembers an error from its results stream and throws it
  on the next `feed` (`session` stops an old stream failing a new one).
- `LiveRunner.feedEngine`: on an error it writes it down (⌃⌘L), marks the
  recording `LiveText.missedAudio`, unloads Parakeet and picks an engine
  again, then feeds the same audio again. 3 failures in a row
  (`triesInARow`): status `.off` ("the speech model ran into a problem. It
  tries again every 30 seconds") and it tries again after 30 s of audio
  (`retryAfter`). Pause/Resume starts the count afresh.
- After it recovers, the status line says "Live text skipped some words...
  the full text comes after you press Stop" (`LiveTranscriber.missedSome`).
  The mini window shows a short "No live text right now" line while off.
- After Stop, `recordingFinal` redoes the text with Parakeet when
  `LiveText.needsRedo` (backup engine OR missedAudio), edits kept. If that
  didn't happen, the transcript offers "Redo with Parakeet".
- File pass (`Transcriber.transcribe`): an error no longer leaves a hole.
  Progress is kept up to the last word; it goes on once by itself with
  Parakeet loaded fresh (`failedOnce`), a second failure in a row shows
  "Transcribing stopped at N min: the speech model ran into a problem."
  with Try again.
- ⌃⌘L: "SPEECH MODEL ERRORS since launch: N" plus the last 8, with the
  time and the place in the audio (`LiveFeed.noteError`). Also notes when
  Parakeet or Apple's engine didn't start.
- HitchMeter removed (the freeze was fixed in 0.1.153). ⌃⌘L keeps the
  live text numbers (behind the mic, start times, mic gaps), now in
  `LiveFeed.report`. The main thread pings and stall samples are gone.
Can't be forced on purpose (the model doesn't fail on demand), so the
test is mostly "nothing got worse".
Test list (for Ryan):
1. Record a minute: live text shows as before, no new messages.
2. ⌃⌘L, paste it in the chat: near the end, "SPEECH MODEL ERRORS since
   launch: 0" (or the errors, if there were any).
3. Stop: the transcript is the same as before (no "Redo with Parakeet"
   offer unless the Mac's built-in engine was used).
4. If you ever see "No live text right now: the speech model ran into a
   problem", tell Claude and paste ⌃⌘L.
