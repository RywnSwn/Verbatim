# Punctuation looks gone (2026-11-20), and the louder mic fix

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Punctuation looks gone (Ryan, 2026-11-20), investigation only
Ryan: live text, text after Stop and imports have no capitals, commas or
quotes any more; "in the past it had basic punctuation like caps and
commas". Checked so far (no code changed):
- The model can write them: `vocab.json` of
  `FluidInference/parakeet-unified-en-0.6b-coreml` has `▁The`, `▁I`, `,`,
  `.`, `?`, `!`, `"`. HF repo unchanged since 2026-09-25; FluidAudio
  pinned at 0.18.0 since 2026-11-10.
- App path keeps them: `ParakeetEngine.words` uses
  `consumeTokenTimings()` (raw tokens, never the vocab rescorer's text),
  `LineBuilder.add`, speaker labels, `Fixes.apply` (keeps lead/trail
  punctuation and capitals) and the views never lowercase or strip.
  `ParakeetEngine` barely changed since step 5c (only `warm`).
- So either "the past" means the Whisper era (before step 5c), or the
  audio reaching Parakeet got worse. Waiting on: a few pasted lines from an
  old and a new recording, plus Copy Layout Details.
- Ryan's wish: "rolling passes as it still records": FluidAudio's batch
  `UnifiedAsrManager` (full-attention 15 s offline encoder, same
  decoder/joint, ~565 MB int8 extra) over each finished minute or so,
  replacing those lines. Breaks "one Parakeet at a time" (8 GB Mac):
  Ryan's call. Unproven that batch punctuates better; test on real audio
  first.
- TESTED on the CI Mac (branch `claude/punctuation-test`,
  `tools/PunctTest`, workflow "Punctuation test", run 44740155927):
  LibriVox "Thunder and Anansi" (413 s), clean and with fake classroom
  echo + noise. Per 100 words (capitals / commas / . ? ! / quotes):
  clean: live 9.5/8.4/5.9/0, batch 9.2/7.7/5.9/0, rolling 60 s
  9.6/7.7/6.0/0, TDT v3 9.9/7.5/6.6/0. Classroom: live 9.1/7.3/5.4/0,
  batch 9.4/7.1/5.4/0, rolling 9.4/6.6/5.3/0, TDT v3 9.5/7.4/6.6/0.
  So: live already punctuates as well as batch; a second pass buys
  nothing (dropped). No Parakeet ever writes quote marks. Bad audio makes
  run-on patches ("...palm tree he determined to reach... reward him how
  to get there") with wrong words too.
- Main suspect now: Nov 19 (RywnSwn/Verbatim#26) Parakeet's 16 kHz audio
  moved from macOS's converter (left channel only) to Verbatim's own
  converter with `downmix = true`. Matches "it used to". Asked Ryan:
  which mic in class, and "Transcribe again" on a recording from before
  Nov 19 (if the punctuation comes back, the audio path is the cause).
- Two-mic test (run 44745032597, fake receiver: left close + light hiss,
  right far: 0.3 volume, 15 ms late, echo, noise), live Parakeet, per 100
  words capitals/commas/stops: left only 9.4/8.4/5.8, averaged
  9.1/8.5/5.6, louder mic 9.4/8.5/5.9 (text same as left only). So
  averaging costs a little in this fake setup, not the big drop Ryan sees;
  the louder mic is at least as good as before Nov 19. Real cause still
  unproven until Ryan's MIC line / Transcribe again test.
- Built on branch `claude/louder-mic` (not merged, no PR: small fix),
  build v0.1.239 (prerelease). `LouderMic` (Audio/LouderMic.swift): 2+
  channel mics are weighted by recent loudness squared (10 ms steps, fast
  rise, slow fall, smooth fade), one-channel mics untouched. Same mono
  sound feeds the 16 kHz and 48 kHz copies. `MicReport` adds a "MIC:" line
  to Copy Layout Details (name, channels, rate, format, weights).
Test list for Ryan (v0.1.239):
1. Record a minute of class (or a video), then Help > Copy Layout Details
   and paste the MIC line to Claude.
2. Are capitals and commas back in the live text? After Stop?
3. If you use the 2-mic receiver: both voices still in the recording and
   the text; no echo when you listen back.
4. Transcribe again on a recording from before Nov 19: caps and commas?
- Ryan tested v0.1.239 (2026-11-20): "the grammar is excellent", loud
  typing and the words still right. But his MIC line was "MacBook Air
  Microphone, 1 ch, 48000 Hz, float32": LouderMic never ran, so the build
  sounds the same as before for him. Cause of the earlier missing
  punctuation NOT proven: likely class audio (far teacher) vs talking
  close, or the app/models having been open a long time. If it comes back
  in class, ask for Copy Layout Details right then (MIC line, live text
  timings). Merged `claude/louder-mic` into main at Ryan's word
  (2026-11-20). `tools/PunctTest` + "Punctuation test" workflow kept for
  reuse (runs only when its files or LouderMic.swift change).
- Next (Ryan): speaker rename UX problems ("the speaker system is
  finicky"), new chat.
