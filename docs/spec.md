# Spec: the small stuff

How Verbatim should behave in the details. Goal: it should feel finished,
not like an empty shell, and not like a bloated mess. If a feature isn't
here or in `PLAN.md`, it probably shouldn't be added without asking Ryan.

Rule of thumb for UX: prefer **undo** over "are you sure?" popups, show
**what is happening** instead of silent waiting, and never lose audio or text.

---

## 1. First launch (onboarding)

One screen, no tour (see `docs/design/`). It shows:

1. **Microphone permission.** One sentence on why, then the system prompt.
   If denied: a clear screen with a button that opens
   System Settings > Privacy & Security > Microphone. No dead ends.
2. **Download the speech model (Parakeet).** One model for live text and
   files. Show the size before downloading ("about 600 MB, one time only").
   Internet in Myanmar can be slow or drop, so:
   - downloads **resume** after a disconnect or app quit
   - a model that doesn't load is downloaded again
   - the app is usable while it downloads: live text uses Apple's built-in
     engine, and Parakeet redoes that recording after Stop once it's here
   - Apple's speech assets (for the backup engine) download the same way
3. No separate test step; Ryan tests with Voice Memos instead.

## 2. Main window

- **Empty state** (no recordings yet): one big Record button, and
  "or drop a Voice Memo here to transcribe it". Not a blank screen.
- **Sidebar:** past recordings, newest first. Each shows name, date,
  length, and a small badge if audio is gone or deleting soon.
- **Recording view:** big timer, Pause/Resume, Stop, Copy. Mic level meter
  so you can see it is actually hearing the class.
- Window size and position are remembered.
- Follows the system light/dark mode. No custom themes.
- Text size: Cmd + / Cmd - (transcript only).
- Cmd+F search inside a transcript.

## 3. Recording edge cases

| Situation | What Verbatim does |
|---|---|
| Mac tries to idle-sleep mid-class | Prevented while recording (power assertion). |
| Lid closed (MacBook sleeps, mic stops) | Can't be prevented. On wake, recording continues and the transcript shows a divider: "Mac was asleep 10:42 to 10:45". Tip shown once: keep the lid open. |
| App crashes or Mac shuts off | Audio is written to disk continuously, transcript autosaved every few seconds. Next launch: "Recover unfinished recording from 10:05?" |
| Cmd+Q while recording | Asks: "Recording in progress. Stop and save, or keep recording?" (the one popup worth having) |
| Window closed while recording | Keeps recording. Menu bar icon shows a tiny waveform + timer; its dropdown has copy, marker, pause, stop. |
| Pressed Stop by accident | Toast: "Recording saved. Undo" for ~10 s. Undo continues the same recording. |
| Forgot to press Stop after class | After ~10 min of silence: notification "Still recording?". Hard stop at a max length (default 3 h). |
| Forgot to Pause during work time | Fine. Silence and quiet chatter are skipped by the voice detector, so no junk text. |
| Pause/Resume | Still one audio file. Transcript shows "Paused 10:12 to 10:20". |
| AirPods connect mid-class | MacBook mic is always the default. Never auto-switches to AirPods (worse quality). AirPods only if picked by hand, with a warning. If the chosen mic disappears, falls back to the MacBook mic and says so in the status spot. Never stops recording. |
| Low battery | Warn at 15%. |
| Disk almost full | Check before starting (need ~200 MB per hour). Warn if low. |
| Starting a second recording | Not allowed while one is running. |
| No internet in class | Everything works offline after the first setup. |

## 4. Transcript behaviour

- **The live text is the transcript** (step 5c, Whisper dropped). Parakeet's
  lines are final as soon as they show, in full ink. Only half-said words
  from Apple's backup engine are lighter. Nothing changes after Stop.
- **New text doesn't yank the screen.** Auto-scroll only if you're already
  at the bottom. If you scrolled up, a "Jump to live" button appears.
- If you're **editing** a line, new words never go into it.
- **Edited lines are locked** (small lock icon). "Transcribe again" keeps
  them, and keeps deleted lines deleted. Click the lock to unlock.
- **Recorded with Apple's backup engine** (Parakeet still downloading):
  after Stop, Parakeet redoes the whole recording by itself.
- **Speaker labels:** voices show as "Speaker 1" (talks the most),
  "Speaker 2"... Click a label to rename that voice everywhere, or to pick
  who said that one line (then the bottom bar offers to change every line in
  that voice). Typed names are offered in every recording. Old recordings
  get labels by themselves once the speaker model is downloaded.
- **Timestamps:** on every line, clock time by default (10:42), with an
  option for time since start (00:37).

## 5. Copy and export

- **Copy** copies everything so far in script format:
  `[Mr. Yurt]: "text"`. Shows "Copied 42 lines". Disabled (with a hint)
  when there's nothing yet.
- Copy menu also has: **Copy new since last copy**, **Copy last 10
  minutes**, **Copy marked parts only**.
- **Markers** (⌘D, toolbar Marker, or right-click a line): flag a moment;
  shows as a flag next to the time. Copies and exports put ⚑ in front of
  marked lines. Undo in the bottom bar.
- **Messages** (mic changes, battery, falling behind, long silence) appear
  in the bottom bar status spot, never as popups.
- **Export** .txt or .md, same script format, no intro, no headings.
  File name: `2026-11-10 English.md`. If it exists: `... (2).md`. Never
  overwrite silently.
- Timestamps in copy/export: setting, default off (cleaner for Claude).

## 6. Corrections memory

- When you edit a word, a small prompt: "Always fix 'Father Nazi' to
  'Anansi'?" Yes / No. Nothing is learned without a yes.
- Fixes are whole-word and smart about capitals, so a rule never breaks
  other words.
- The **word list** (names like Nyankupon, Anansi, Kweku Tsin) boosts those
  words in Parakeet, live and in files (FluidAudio vocabulary boosting,
  ~100 MB extra download). Fix rules catch whatever it still misses.
- A Words screen in Settings to see, edit and delete rules (in case one
  was a mistake).
- Starts pre-filled with the known hard names.

## 7. Storage and privacy

- Audio auto-deletes after 7 days (setting). Transcripts are kept forever.
- Audio is **never** deleted while its transcription isn't finished.
- Sidebar badge "audio deletes in 2 days".
- Storage screen: list of recordings with sizes, total used, delete buttons.
- Deleting a recording moves it to an in-app "Recently deleted" for a few
  days (undo), not gone instantly.
- Everything stays on the Mac. No accounts, no cloud, no analytics.

## 8. Transcribe a file (Voice Memo mode)

- Drag a file onto the window, or File > Transcribe a recording.
- Accepts .m4a (Voice Memos), .mp3, .wav, and the audio from .mp4/.mov.
- Progress bar with time left, and Cancel. About a minute for a 1 h class.
- Waits while a recording is going (one model in memory on an 8 GB Mac),
  and says so.
- The file is copied in, so the 7-day rule deletes the copy, never your
  original.
- Unsupported file: a clear message saying which types work.

## 9. Settings (kept small on purpose)

**General**
- Microphone (default: MacBook mic, never auto-switches to AirPods)
- Timestamps: clock time / time since start

**Transcription**
- Advanced (collapsed): live engine choice, for comparing engines

**Words**
- Word list and fix rules

**Storage**
- Keep audio for: 7 days
- Storage screen

**Updates**
- Check for updates automatically (on by default), Check now

Not adding: themes, cloud sync, accounts, summaries, AI chat inside the app.

## 10. Updates and moving to a new Mac

- Minimum macOS 26 (Tahoe). Apps keep working on newer macOS versions, so
  a new Mac with macOS 27, 28, etc. runs the same app.
- All data lives in `~/Library/Application Support/Verbatim`. Apple's
  Migration Assistant copies it to a new Mac automatically.
- Settings > Storage also has "Export everything" (a zip of all
  transcripts and settings) as a manual backup.
- Saved files carry a format version number, so future updates can read
  old transcripts without breaking them.
- The speech model is stored outside the app, so updates are small and
  don't re-download it.
