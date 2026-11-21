# Step 7c: voice memory

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## How voice memory works (step 7c)
- `Model/VoiceLibrary.swift`. Renaming a voice to a real name ("Rename
  Speaker 1 everywhere", or "Change them too" with a name) saves up to 20 s
  of it (longest lines first, 8 s max from each, edges trimmed) in App
  Support/Verbatim/Voices (`voices.json` + `<id>.f32`). Same name again
  replaces the old clip. Needs 6 s or more, and the audio.
- `SpeakerEngine.begin(known:)` plays the clips to Sortformer first
  (`enrollSpeaker`, `overwritingAssignedSpeakerName: false`); the slot each
  lands in gets the name in `LiveText.voiceNames` (`newVoiceSession(names:)`).
  Live recording, file passes and Find speakers all do this.
- At most 3 known voices per session (newest switched-on ones), so one of
  Sortformer's 4 slots stays free for new people.
- Bottom bar after renaming: "... Verbatim will know this voice next time.
  Undo" (undo takes back the name and the saved voice).
- Settings > Voices: list, tick to use, Forget... (asks first).
- Risk to check with Ryan: a known voice that isn't in the recording keeps
  a slot; someone who sounds similar might get that name. Fix by renaming.

## Step 7c test list for Ryan
1. In a recording with speakers, click Speaker 1 > Rename everywhere, type
   a name: the bottom bar says Verbatim will know this voice next time.
2. Settings > Voices: the name is there, "From ..., 20 s".
3. Record or import something new with the same person: their lines say
   the name from the start, not "Speaker 1".
4. Record a video with other people: does anyone wrongly get that name?
5. Settings > Voices: untick it, record again: back to "Speaker 1".
