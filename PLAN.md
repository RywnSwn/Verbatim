# Plan

Status: steps 1, 2, 3 built 2026-11-09, step 11 (updates) pulled forward
and built the same day because manual installs were annoying Ryan.
Waiting for Ryan to add the SIGNING_CERT_P12 secret, then install one
signed build by hand; after that updates are in-app. Step 3 not tested yet.
Next: step 4 (live).
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
4. [ ] **Live transcript.** Live engine while recording, swappable.
       Test Apple SpeechAnalyzer and NVIDIA Parakeet (the model OpenWhispr
       uses) first.
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
11. [~] **Updates.** In-app update button (own updater, not Sparkle).

## Nice to have (after the above)
- [ ] Timeline: click a line to hear that bit of audio.
- [ ] Engine comparison screen for live engines.

## Open questions
- Which live engine is good enough (test SpeechAnalyzer vs others).
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
