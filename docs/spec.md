# Spec: the small stuff

How Verbatim should behave in the details. Goal: it should feel finished,
not like an empty shell, and not like a bloated mess. If a feature isn't
here or in `PLAN.md`, it probably shouldn't be added without asking Ryan.

Rule of thumb for UX: prefer **undo** over "are you sure?" popups, show
**what is happening** instead of silent waiting, and never lose audio or text.

---

## 1. First launch (onboarding)

Three short steps, then straight into the app. Skippable steps stay
reachable later from Settings.

1. **Microphone permission.** One sentence on why, then the system prompt.
   If denied: a clear screen with a button that opens
   System Settings > Privacy & Security > Microphone. No dead ends.
2. **Download the Whisper model.** Show the size before downloading
   (e.g. "about 600 MB, one time only"). Internet in Myanmar can be slow or
   drop, so:
   - downloads **resume** after a disconnect or app quit
   - the file is checked after download (size/hash) so a broken file never loads
   - the app is usable while it downloads (live transcript works, accurate
     pass waits and says so)
   - Apple's speech assets (for the live engine) download the same way
3. **Quick test.** "Say something." Live text appears. Builds trust before
   using it in class.

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
| Window closed while recording | Keeps recording. Menu bar icon shows a red dot + timer, click to reopen. |
| Pressed Stop by accident | Toast: "Recording saved. Undo" for ~10 s. Undo continues the same recording. |
| Forgot to press Stop after class | After ~10 min of silence: notification "Still recording?". Hard stop at a max length (default 3 h). |
| Forgot to Pause during work time | Fine. Silence and quiet chatter are skipped by the voice detector, so no junk text. |
| Pause/Resume | Still one audio file. Transcript shows "Paused 10:12 to 10:20". |
| AirPods connect mid-class | Doesn't auto-switch the mic (Bluetooth mics sound worse). Stays on the chosen mic. If the chosen mic disappears, falls back to built-in and shows a notice. Never stops recording. |
| Low battery | Warn at 15%. In Low Power Mode, the background accurate pass pauses and catches up at Stop. |
| Disk almost full | Check before starting (need ~200 MB per hour). Warn if low. |
| Starting a second recording | Not allowed while one is running. |
| No internet in class | Everything works offline after the first setup. |

## 4. Transcript behaviour

- **Live text looks slightly different** (lighter grey) from accurate text,
  so you can tell what has been upgraded. Subtle, not distracting.
- **Upgrades don't yank the screen.** Auto-scroll only if you're already at
  the bottom. If you scrolled up, a "Jump to live" button appears.
- If you're **selecting or editing** a line, the background pass doesn't
  touch it until you're done.
- **Edited lines are locked** (small lock icon). Later passes never change
  them. Click the lock to unlock.
- **Chunk seams:** the overlap between chunks is merged so words aren't
  doubled or dropped.
- **Whisper hallucinations** (it invents "Thank you for watching!" on
  silence): only speech parts go to Whisper, and known junk phrases are
  filtered out.
- **Speaker labels:** teacher name comes from settings (default
  "Mr. Yurt"). Click a label to fix it. Renaming a speaker renames all
  their lines in that recording.
- **Timestamps:** on every line, clock time by default (10:42), with an
  option for time since start (00:37).

## 5. Copy and export

- **Copy** copies everything so far in script format:
  `[Mr. Yurt]: "text"`. Shows "Copied 42 lines". Disabled (with a hint)
  when there's nothing yet.
- **Copy new** (small option): only lines since your last copy, for
  sending follow-up chunks to Claude mid-class.
- **Export** .txt or .md, same script format, no intro, no headings.
  File name: `2026-11-10 English.md`. If it exists: `... (2).md`. Never
  overwrite silently.
- Timestamps in copy/export: setting, default off (cleaner for Claude).

## 6. Corrections memory

- When you edit a word, a small prompt: "Always fix 'Father Nazi' to
  'Anansi'?" Yes / No. Nothing is learned without a yes.
- Fixes are whole-word and smart about capitals, so a rule never breaks
  other words.
- The **word list** (names like Nyankupon, Anansi, Kweku Tsin) is fed to
  Whisper as a hint. Whisper only reads ~200 tokens of hint, so the most
  used / most recent words go first.
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
- Progress bar with time left, and Cancel.
- The file is copied in, so the 7-day rule deletes the copy, never your
  original.
- Unsupported file: a clear message saying which types work.

## 9. Settings (kept small on purpose)

**General**
- Teacher name (default Mr. Yurt), student label (default Student)
- Microphone (default: built-in)
- Timestamps: clock time / time since start

**Transcription**
- Whisper model: a short list with size and speed, one marked Recommended
- Background pass every: 5 min (default)
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
- The Whisper model is stored outside the app, so updates are small and
  don't re-download it.
