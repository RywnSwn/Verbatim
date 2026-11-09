# Plan

Status (end of chat 2026-11-09, second chat): steps 1, 2, 3, 11 merged
into `main`. Step 4 (live transcript) built on branch
`claude/kind-maxwell-oq9tl5`, waiting for Ryan to test (he tests
tomorrow, together with his step 3 results).
Next: Ryan's step 3 + step 4 feedback, fix what he reports, merge step 4.
Then step 2b (visual design) or step 5.
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
2b. [ ] **Visual design.** Fonts, colors, spacing on the real SwiftUI app
       (not a web mockup). Ideas: serif for big moments and maybe the
       transcript, system font for controls.
3. [~] **Transcribe a file.** Drop a Voice Memo, WhisperKit transcribes it,
       model download with resume. Ryan tests accuracy on real classes.
4. [~] **Live transcript.** Parakeet Unified (main) + Apple SpeechAnalyzer
       (backup while Parakeet downloads). Built, not tested yet.
5. [ ] **Background accurate pass.** Voice detector cuts ~5 min chunks at
       pauses, one job at a time, overlap merge, live text upgrades.
6. [ ] **Transcript tools.** Timestamps, edit + lock, Copy / Copy new,
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
- [ ] Timeline: click a line to hear that bit of audio.
- [ ] Engine comparison screen for live engines.

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
- No app icon yet (generic icon). Add in the visual design step.

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
- Double-click a line: inline field. Enter saves, Esc cancels, clicking away
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
- Text in lines is no longer selectable outside edit mode (double-click
  would select a word instead of editing). Copy this line / Copy from here
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
9. While recording, double-click a line, fix a word, press Enter: lock
   shows, new words keep coming below. Undo in the bottom bar works.
10. Right-click a line > Delete line, then Undo.
