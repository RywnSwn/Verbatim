# Plan

Status: planning finished 2026-11-09, nothing built yet.

## Must have
- [ ] Record the whole class, with Pause and Resume (class has work time).
      One recording file even with pauses.
- [ ] LIVE transcript while recording. A few seconds of delay is fine.
- [ ] Accurate background pass during recording: every ~5 min, re-transcribe
      only the new audio (plus a little overlap) with Whisper. Live text
      upgrades to accurate text behind the user. One job at a time.
- [ ] Final pass on Stop: only the last few minutes are left, so it is fast.
- [ ] Copy button: copies everything transcribed so far (Ryan sends it to
      Claude mid-class to ask questions).
- [ ] Timestamps on every line.
- [ ] Speaker labels (Mr. Yurt vs Student), at least on the accurate pass.
- [ ] Export .txt and .md in script format, one line per turn:
      `[Mr. Yurt]: "text"` (no intro, no headings).
- [ ] Edit lines. Edited lines are LOCKED: later passes never overwrite them.
- [ ] Corrections memory: each fix goes into a word list / replacement map
      used on future transcripts (Whisper initial prompt + find/replace).
- [ ] Audio auto-deletes after 7 days. Storage screen to see and delete
      recordings early. Transcripts are kept after audio is deleted.
- [ ] "Transcribe a recording" mode (feed in a Voice Memo) for testing at
      home before trusting the app in class.

## Nice to have
- [ ] Timeline: click a line to hear that bit of audio.
- [ ] In-app "update available" button (e.g. Sparkle).
- [ ] Swappable live engine so different models can be compared.

## Open questions
- Confirm stack with Ryan (Swift + WhisperKit is the lean).
- Which live engine is good enough (Ryan heard Apple's dictation is weak).
- Whisper model size that fits 8 GB and is fast enough.
- macOS version on Ryan's Mac.
- How speaker labels work offline on Mac (diarization model choice).

## Testing plan
Record a few classes with Voice Memos, run them through the app at home,
keep Claude dictate as backup in class until Verbatim proves itself.
Ask Mr. Yurt before recording class.
