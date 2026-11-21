# In-app player and audio shrink after Stop (2026-11-10)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). The 48 kHz listening copy came later: `listen-audio-add-line.md`.

## How the in-app player works (2026-11-10, Ryan's ask)
- `Audio/Playback.swift`: one `AVAudioPlayer` at a time, speed 1x to 2x
  (saved in UserDefaults), remembers where each recording was left while
  the app is open. `Views/PlayerBar.swift`: bar under a finished
  transcript (back/forward 15 s, play/pause, slider, speed, close).
- Opened by the Play button in the toolbar, Recording > Play or Pause
  Audio (Option-Cmd-P), sidebar right-click > Play Audio, clicking a
  line's time, or right-click a line > Play from here.
- The word being heard gets a light blue mark (Ryan's ask). Estimated
  from the line's start/end by word length until step 5c saves real word
  times. The ticker runs every 0.12 s for this.
- The line being heard is shaded and its time turns ink blue; the view
  follows it unless you scrolled in the last 8 s or are editing/searching.
- Closes when recording starts (mic would hear the speakers) or another
  recording is picked. Not shown on the recording in progress.
- Delete Audio Only (sidebar right-click and the More menu, shows the
  size): moves audio.wav to the Mac's Trash, Undo for 10 s,
  `RecordingInfo.audioDeletedAt` set, sidebar says "no audio", Play and
  Transcribe again are disabled. Not while recording or transcribing that
  recording. If the text isn't finished it asks first (spec: never delete
  audio before its text is done). Step 9's 7-day auto delete should reuse
  `RecorderModel.deleteAudio`.

## In-app player test list for Ryan
1. Open a finished recording, press Play in the toolbar: the bar shows at
   the bottom, sound plays in the app (no Apple Music).
2. Drag the slider, try back/forward 15, change speed to 1.5x.
3. Click a time on the left of any line: plays from there, that line is
   shaded and the word being said is marked in light blue (does it keep
   up, or run ahead/behind?). Clicking the text itself still edits it.
4. Scroll away while it plays: it stops following for a few seconds.
5. Pick another recording: the audio stops.
6. Right-click a recording in the sidebar > Delete Audio Only (size shown):
   text stays, sidebar says "no audio", Undo in the bottom bar works.

## Audio shrink after Stop (2026-11-10, Ryan's ask)
- `Audio/AudioSquash.swift`: WAV (~115 MB/h, crash safe while recording)
  becomes AAC 32 kbps in `audio.m4a` (~14 MB/h) once the recording is
  final (Undo Stop over), not queued/being transcribed, not importing, and
  nothing is recording. New file's length is checked before the WAV goes.
  Failures keep the WAV (retried next launch). Old recordings shrink too,
  one at a time, starting at launch.
- `RecordingStore.audioURL` = m4a if present, else WAV; writers use
  `wavURL`. `AudioReader` (AVAudioFile, opened once) reads either for
  Transcriber. Not live while recording: an unfinished AAC file can be
  lost in a crash (Ryan agreed).
- Test: record 1 min, Stop, wait 15 s: Finder shows audio.m4a, no WAV;
  Play and Transcribe again still work; "Delete Audio Only" shows the
  small size. Old recordings shrink after the update.
