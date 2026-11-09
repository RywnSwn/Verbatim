# Plan

Status (end of chat 2026-11-09, fourth chat): steps 1, 2, 2b, 3, 4, 5 and 11
merged into `main`. Step 2b merged (Ryan asked to merge before testing; its test
list is below). Step 5 is still not tested
by Ryan: ask him to run the "Step 5 test list" below. Also still
unanswered: line editing on a real Mac, step 3 accuracy on a real class
Voice Memo.
Next: step 6. App icon later.
Behaviour and edge cases: `docs/spec.md`. Layout to build to:
`docs/design/README.md`.

## Build order (one milestone per chat)

Order is chosen so Ryan can test real accuracy at home early, before any
class depends on it.

0. [x] **Layout design.** Approved mockup in `docs/design/`.
1. [x] **Skeleton + build.** SwiftUI app, GitHub Actions builds a zipped
       .app into GitHub Releases. Ryan downloads and opens it.
2. [x] **Record.** Record / Pause / Resume / Stop into one crash-safe audio
       file. Sleep prevention, mic picker, level meter, crash recovery.
2b. [x] **Visual design.** "Notebook" look picked by Ryan and built.
       App icon still to do (Ryan didn't like the first try: a waveform
       turning into text lines; do it later, show him options first).
3. [~] **Transcribe a file.** Drop a Voice Memo, WhisperKit transcribes it,
       model download with resume. Ryan tests accuracy on real classes.
4. [x] **Live transcript.** Parakeet Unified (main) + Apple SpeechAnalyzer
       (backup while Parakeet downloads).
5. [x] **Background accurate pass.** Voice detector cuts ~5 min chunks at
       pauses, one job at a time, overlap merge, live text upgrades.
6. [ ] **Transcript tools.** Timestamps, (edit + lock done in step 4), Copy / Copy new,
       export .txt/.md, search.
7. [ ] **Speaker labels.** Teacher vs Student, click to fix.
8. [ ] **Corrections memory.** Word list as Whisper hint, confirmed fix
       rules, Words screen.
9. [ ] **Storage.** History sidebar, 7-day audio delete, Storage screen,
       Recently deleted, Export everything.
10. [ ] **Polish.** First-launch screen, menu bar dropdown, Settings, notifications,
        all the edge cases in `docs/spec.md` that aren't done yet.
11. [x] **Updates.** In-app update button (own updater, not Sparkle).

## Nice to have (after the above)
- [ ] Timeline: click a line's time to hear that bit of audio (clicking the text edits it).
- [ ] Engine comparison screen for live engines.
- [ ] Auto-name recordings from what was said (Ryan's ask), e.g.
      "English: Anansi and the sky god", with Apple's on-device
      Foundation Models (offline, free). Needs Apple Intelligence on.
      Ryan can still rename.

## Open questions
- Is Parakeet's live text good enough in a real class? Is 2 s delay OK?
- Does Apple's engine need the Speech Recognition permission at all?
  (We ask only when it's actually used.)
- Is large-v3 turbo (626 MB) fast enough on Ryan's M2? Test in step 3.
- How speaker labels work offline (diarization model choice, milestone 7).
- Is Ryan's Mac a MacBook Air (no fan, slows down when hot) or Pro?
- Should a recording be able to "Keep audio" past 7 days?

## Testing plan
Record a few classes with Voice Memos, run them through the app at home,
keep Claude dictate as backup in class until Verbatim proves itself.
Ask Mr. Yurt before recording class.

## How the build works (step 1)
- `Package.swift`: Swift package, macOS 26, one executable target.
- `scripts/build-app.sh`: `swift build`, wraps the binary in Verbatim.app with
  `Support/Info.plist` (mic permission text), ad-hoc signs, zips. Works with
  only Command Line Tools too.
- `.github/workflows/build.yml`: every push builds on `macos-26` and creates a
  GitHub Release `v0.1.<run number>` with Verbatim.zip. Branch builds are
  marked pre-release; builds from `main` are the normal latest release.
- First open of the unsigned app: double-click, then System Settings >
  Privacy & Security > "Open Anyway" (right-click > Open no longer skips
  the warning on recent macOS).
- No auto update yet: Ryan downloads each new build by hand until step 11.
- No app icon yet (generic icon). Ryan wants to pick one later.

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

## How transcription works (step 3)
- WhisperKit 1.1.1 from `argmax-oss-swift`, model
  `large-v3-v20240930_626MB`, stored in
  `~/Library/Application Support/Verbatim/Models` (outside the app, so
  updates don't re-download). Only `Transcribe/WhisperEngine.swift` imports
  WhisperKit.
- Download starts on first launch; WhisperKit's downloader resumes partial
  files. Our side: progress, time left, Pause, auto retry every 20 s.
  After download the model is loaded once ("Getting the model ready") to
  fetch the tokenizer while online and let macOS optimise it.
- `Transcribe/Transcriber.swift`: queue, one job at a time, model unloaded
  when idle. Each job cuts the WAV into ~2 min pieces at the quietest
  0.1 s near the cut, transcribes, shifts times, saves `transcript.json`
  after every piece (so text appears as it goes; Cancel and crashes keep
  progress; Continue resumes). Junk phrases ("Thanks for watching") dropped.
  Step 5 should reuse this piece logic.
- Recordings are queued 10 s after Stop (when Undo Stop expires). On launch,
  unfinished ones are re-queued unless Ryan pressed Cancel.
- Import: drop a file on the window or Cmd+O. `AudioImport` converts it
  to our WAV with AVAssetReader, original untouched. Imports show time
  since start in the gutter, recordings show clock time (pauses skipped).
- Transcript view: status line on top, time gutter, Copy all (Shift+Cmd+C,
  plain text, no speakers yet), More menu (Play audio, Show in Finder,
  Transcribe again, Move to Trash).

## Step 3 test list for Ryan
1. First launch: model download line on the start screen, Pause/Resume.
2. After download: "Getting the model ready", then "ready".
3. Old recordings get text by themselves. Text appears piece by piece.
4. Drop a real class Voice Memo: accuracy? names? how long did it take?
5. Copy all, paste into Claude.
6. Cancel halfway, then Continue.

## How updates work (step 11, pulled forward)
- `Updates/Updater.swift`: on launch and every 4 h, reads
  api.github.com/repos/RywnSwn/Verbatim/releases, picks the highest build
  number (tag v0.1.N) above CFBundleVersion, including pre-releases when
  "Include test builds" is on (default on: Ryan tests branch builds).
  Downloads Verbatim.zip to App Support/Verbatim/Updates/<N>/, unzips with
  ditto, checks `codesign --verify -R=<this app's designated requirement>`
  (identifier only while builds are ad-hoc). Bottom bar: "Version X is
  ready. Restart to update". A bash script waits for quit, swaps the app
  (old kept until the swap works), clears quarantine, reopens.
- Caveat: newest build number wins across branches, so a docs push to
  main after a step branch build can "update" to a build without that
  step. Keep branch work merged promptly.
- Signing: self-signed code signing cert "Verbatim (RywnSwn)", SHA-1
  92:25:9A:B0:98:12:A9:30:E5:E2:9E:81:9F:43:E8:54:E3:F6:BB:04, valid to
  2046. The p12 (password `verbatim`) is only in the GitHub secret
  SIGNING_CERT_P12, never in the repo. CI imports it into a temp
  keychain; without the secret, builds fall back to ad-hoc. Same cert ==
  stable designated requirement == macOS keeps the mic permission.
- `Updates/Uninstaller.swift`: Verbatim > Remove Verbatim and Its Data
  trashes the app, App Support/Verbatim, caches, prefs, saved state and
  resets the mic permission (tccutil).

## Sidebar buttons (added at the end of chat 2026-11-09, Ryan's asks)
- Top: "+ New recording ⌘R", like New chat in Claude. One click starts
  recording; while recording it reads "Recording now" and jumps to it.
- Bottom: "Transcribe a file…" (same as Cmd+O / drag and drop).
- Updater says "Updated to version X" once after an update.

## How live text works (step 4)
- Engine: NVIDIA Parakeet Unified 0.6B (English, punctuation, ~2 s behind
  speech, int8 encoder on the Neural Engine) through FluidAudio 0.18.0
  (`exact:`, `traits: []` so its TTS/diarizer/text-normaliser parts are left
  out). Only `Live/ParakeetEngine.swift` imports FluidAudio.
- Download: ~600 MB to `App Support/Verbatim/Models/Live/parakeet-unified-en-0.6b-coreml`,
  starts on first launch next to the Whisper download, resumes, Pause, auto
  retry every 20 s, then loaded once ("Getting live text ready") and freed.
  Flag `liveModelPrepared` in UserDefaults.
- Backup: Apple SpeechAnalyzer (`Live/AppleSpeechEngine.swift`) when
  Parakeet isn't ready at the moment the mic starts. Its English model is
  requested at launch while Parakeet is missing. Speech Recognition
  permission is asked only then (Info.plist has the text).
- Swappable: `LiveEngine` protocol (`begin` / `feed` / `end`).
- Flow: `AudioPipeline.onSamples` gives every saved sample (Float, 16 kHz)
  to `LiveFeed` (an AsyncStream), `LiveRunner` feeds the engine in order.
  Pause/sleep/disk-full send `.flush` (last words finished, engine reset);
  the engine is picked again when audio comes back, so Parakeet takes over
  from Apple after the next Pause. Times are seconds into audio.wav (the
  runner counts samples), so they line up with Whisper's.
- Memory: Parakeet loaded at the first audio, unloaded after Stop (before
  Whisper starts 10 s later). If no engine can listen, it looks again
  every 15 s of audio.
- Lines: `LineBuilder` joins words; new line after a sentence end (70+
  chars), a pause over 1.6 s, or 260 chars.
- Saved to `Recordings/<id>/live.json` (formatVersion 1) every 10 s and at
  Pause/Stop. Undo Stop keeps adding to it.
- Screen: live lines a little grey; status line on top only when Apple's
  engine or nothing is listening. Auto-scroll only at the bottom, else
  "Jump to live". Copy all works while recording. After Stop, live lines
  the accurate pass hasn't reached show grey under "Checked up to 10:40".
- Step 5 should replace the grey live part with Whisper text as each chunk
  finishes, during recording. It must keep lines with `locked: true`
  (Ryan edited them) and skip text inside `LiveText.removed` spans (lines
  he deleted), or his changes come back.

## Editing lines (pulled forward from step 6, Ryan's ask while testing step 4)
- Click a line (one click, Ryan's ask; was double-click): inline field.
  Text cursor shows over lines. Enter saves, Esc cancels, clicking away
  saves, emptying it deletes. Right-click: Copy this line, Copy from here
  down, Edit line, Delete line, Unlock.
- Works on live and accurate lines, while recording and after.
- Edited lines get `locked: true`, turn full ink, show a lock (click to
  unlock). New live words never go into a line being edited or locked.
- "Line edited. Undo" / "Deleted a line. Undo" in the bottom bar for 10 s.
- Lines are found by their start time (`Model/LineEdits.swift`).
- Transcriber re-reads the lines on screen before adding each piece, so
  edits made while it transcribes are kept. "Transcribe again" still
  throws edits away (explicit action).
- Text in lines is no longer selectable outside edit mode (a click
  would select text instead of editing). Copy this line / Copy from here
  down / edit mode cover copying part of it.

## Step 4 test list for Ryan
1. Start screen: "Downloading live text model" line with %, Pause works.
   Then "Getting live text ready", then "Live text ready".
2. Record yourself reading something aloud: text appears ~2 s behind, in
   grey, with punctuation. Names? (Nyankupon, Anansi, Kweku Tsin)
3. Scroll up while it records: it stops following, "Jump to live" shows.
4. Pause, Resume: last words before Pause show up, carries on fine.
5. Copy all while recording, paste into Claude.
6. Stop: live text stays (grey) until the accurate text replaces it.
7. Activity Monitor > Memory: how much Verbatim uses while recording.
8. If you record before Parakeet finishes: a line says it's using the
   Mac's built-in engine. Does that text look OK?
9. While recording, click a line, fix a word, press Enter: lock
   shows, new words keep coming below. Undo in the bottom bar works.
10. Right-click a line > Delete line, then Undo.

## How the background accurate pass works (step 5)
- `Transcriber.growing`: recordings still getting audio (recording, paused,
  or in the 10 s Undo Stop window). `RecorderModel` calls
  `recordingStarted` (start, Undo Stop), `audioGrew` (every 10 s) and
  `recordingFinal` (when Undo Stop expires; replaces the old enqueue).
- A chunk starts once there are 5 min + 15 s of unchecked audio
  (`chunkSeconds`, `settleSeconds`). The 15 s lets live text for that bit
  become final.
- Cut: the longest gap between live lines in the 30 s before the 5 min
  mark, at its quietest 0.1 s, so live lines are never split. No live text:
  quietest moment in the 20 s before the mark (`WavReader.quietPoint`).
- Overlap: each piece starts 1 s before the cut. Whisper runs with word
  timestamps; `Transcribe/ChunkMerge.swift` drops words whose middle is
  before the cut, inside a deleted live line (`LiveText.removed`) or inside
  a locked live line, then adds the locked live lines as they are. A line
  belongs to the side of the cut its middle is on (`Line.middle`,
  `LiveText.unchecked(after:)`).
- Prompt: the last 3 checked lines (max 300 chars, 120 tokens) go to
  Whisper as context. Segments that just repeat the prompt are dropped.
  Step 8 adds the word list in `Transcriber.promptText`.
- While Ryan edits a live line inside the chunk, the merge waits until he
  is done. Undo of a live edit/delete after the line got upgraded applies
  to the checked text (`LineEdits.restore`).
- The recording in progress jumps ahead of imports: a file job yields after
  its current piece when a recording chunk is ready.
- Memory: Whisper loads for each chunk and unloads after (queue empty), so
  during class it is in memory only while checking. Parakeet stays loaded.
- Low Power Mode: chunks wait, bottom bar says so, and everything catches
  up after Stop (spec). Turning it off starts a waiting chunk.
- Screen: recording view shows checked text, the "Checked up to" divider,
  then grey live text. Bottom bar status spot: "Checking 10:40 to 10:45".
- Post-stop and imported files use the same code (2 min pieces, overlap,
  word merge).
- Not done: "falling behind" message, Settings choice for the 5 min
  (both step 10). Possible screen jump when a chunk lands while scrolled up:
  ask Ryan.

## Step 5 test list for Ryan
1. Record 12+ min (a video or podcast is fine). Around 5:15 the bottom
   right says "Checking ..." for a bit, then the top part turns from grey
   to black with "Checked up to ..." under it. Again around 10:30.
2. Read the seam around the 5 min mark: any doubled or missing words?
3. While recording, delete a grey line and edit another one before they
   get checked. After the check: deleted stays gone, edited stays as you
   wrote it with the lock.
4. Scroll up while a check lands: does the screen jump?
5. Stop: the last few minutes get checked within a minute or so.
6. Activity Monitor: memory while "Checking" shows vs between checks.
7. Turn on Low Power Mode while recording: bottom right says checking
   waits. Stop: it catches up.
8. Import a Voice Memo, then start recording: the recording's checks still
   happen during the import.

## How the look works (step 2b)
- Ryan compared three looks on a preview page
  (https://claude.ai/artifact/WQapwdfhQBtu6R5yFrHHuN): A Notebook, B Plain
  Mac, C Graphite. He picked A, but asked why Copy all was blue, so the
  main button is ink instead.
- `Views/Theme.swift`: colors (paper, ink, line, accent ink blue) with
  light and dark values, transcript font (New York serif 17, line spacing
  5, 14 between lines), `InkButtonStyle` (`.ink`, `.inkLarge`) for the one
  main button per screen.
- Main area and bottom bar on paper; sidebar, Settings and menus stay
  standard Mac. App tint is the ink blue (links, progress, toggles).
- Copy all sits in its own toolbar item with the glass background hidden,
  so it shows as an ink capsule.
- "Checked up to" divider in serif italic. Live text 62% ink, half-said
  words 45%.
- App icon: not yet. First try (waveform bars + text lines, drawn with
  Pillow) was rejected by Ryan. Next time show a few options first; to
  add one, put `AppIcon.icns` in `Support/`, copy it in
  `scripts/build-app.sh`, and set `CFBundleIconFile` in Info.plist.

## Step 2b test list for Ryan
1. Update, open an old transcript: serif text, warm white, ink Copy all.
2. Switch the Mac to dark mode (System Settings > Appearance): still
   easy to read? Copy all turns light.
3. Record a minute: live grey text readable? "Checked up to" line looks OK?
4. Anything that looks off or cramped: tell Claude in plain words.
