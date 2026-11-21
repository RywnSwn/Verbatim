# Step 7: speaker labels

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). The newer speaker menu is in `speaker-menu.md`.

## How speaker labels work (step 7)
- Model: NVIDIA Sortformer through FluidAudio (trait `Diarizer` turned on in
  `Package.swift`), "balanced" v2.1, 6-bit (palettized): ~100 MB download,
  light on memory, about 1.5 s behind the audio, up to 4 voices at once.
  Picked over LS-EEND (more false alarms) and pyannote (worst in noise).
  Nemotron 3 (8 voices) is gated on Hugging Face, so not usable yet.
- `Live/SpeakerEngine.swift`: the engine, `VoiceFrames` (which voice in
  every 0.08 s) and `SpeakerModel` (download, after Parakeet is ready;
  saved in Models/Live next to Parakeet). Start screen shows its progress
  under "Speech model ready".
- Live: `LiveRunner` feeds the same samples to it (before Parakeet, so it's
  ahead), for the whole recording including pauses. Each word gets the voice
  heard most during it; a new voice starts a new line (`LineBuilder`).
- Files (imports, Transcribe again): `Transcriber` runs it next to Parakeet.
- "Find speakers": recordings with text but no voices (old ones, or made
  before the model was here) get a speakers-only pass by themselves after
  the model downloads, one at a time, after any files, waiting while
  recording. Lines are split at the word where the voice changes (one-word
  changes are ignored). More menu > "Find speakers again" redoes it.
- Saved: `Line.voice` (number, = listening session * 4 + Sortformer slot),
  `Line.speaker` (Ryan's pick for one line), `LiveText.voiceNames` (Ryan's
  pick for a whole voice), `voiceSessions`, `speakersFound`.
- Names (`Model/Speakers.swift`), changed the same day at Ryan's ask (he
  uses it for videos too, not only Mr. Yurt's class): voices show as
  "Speaker 1" (talks the most), "Speaker 2"... Click a name: "Rename
  Speaker 1 everywhere..." (all its lines), or pick who said this one line
  (this recording's speakers + names typed before, kept in UserDefaults
  `recentSpeakerNames`, newest first, 8 max), or "Someone else...". After
  a one-line change the bottom bar offers "Change them too", then Undo.
  Stored as a name or "#v5" (same as voice 5).
- "Find speakers again" drops voice renames (the voice numbers are new).
- Copy: `[Mr. Yurt]: "text"`; Markdown export: `**Mr. Yurt:** text`. Lines
  with no speaker stay plain.
- Old Whisper lines (transcript.json) never get speakers.

## Step 7 test list for Ryan
1. Update (test build from the step 7 branch). Start screen: "Downloading
   speaker labels" under "Speech model ready", then it goes away.
2. Old recordings: "Finding who said what" at the top, then "Speaker 1:"
   etc. appear. Is the person who talks most Speaker 1?
3. Record a video with two people talking: names show up live, a new line
   when the speaker changes.
4. Click "Speaker 1" > Rename everywhere, type a name: all their lines
   change. Undo works.
5. Open another recording, click a name: the name you typed is in the
   list. Pick it, then "Change them too".
6. Copy all, paste: `[Name]: "..."` lines.
7. In class (with Mr. Yurt's OK): are students picked up, or missed?
