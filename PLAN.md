# Plan

Status (2026-11-10, step 5c chat): steps 1, 2, 2b, 3, 4, 5, 6 and 11 merged
into `main`. Step 5c (drop Whisper, Parakeet only) is built on branch
`claude/step-5c-parakeet-only`, PR open, not tested by Ryan yet: ask him to
run the "Step 5c test list" below. Steps 2b and 6 also not tested yet (their
test lists are below). Step 5's test list is gone with Whisper.
Still unanswered: line editing on a real Mac.
Next: step 7. App icon later.
Question for Ryan: markers (⌘D, "Copy marked parts only") are in the spec
and layout but in no step. Add them to step 7 or 10, or drop them?
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
3. [x] **Transcribe a file.** Drop a Voice Memo, it gets transcribed (was
       WhisperKit, Parakeet since step 5c), model download with resume.
4. [x] **Live transcript.** Parakeet Unified (main) + Apple SpeechAnalyzer
       (backup while Parakeet downloads).
5. [x] **Background accurate pass.** Whisper checked 5 min chunks during
       class. Removed again in step 5c.
6. [x] **Transcript tools.** Timestamps, (edit + lock done in step 4), Copy / Copy new,
       export .txt/.md, search. Merged, not tested by Ryan yet.
5c. [x] **Drop Whisper, Parakeet only** (Ryan's call, 2026-11-10). Built,
       PR open, not tested by Ryan yet. See "How file transcription works".
7. [ ] **Speaker labels.** Teacher vs Student, click to fix.
8. [ ] **Corrections memory.** Word list via Parakeet vocabulary boosting
       (~100 MB extra download, Ryan said yes), fix rules, Words screen.
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

## How file transcription works (step 5c, Whisper dropped)
- Recordings: the live text (`live.json`) IS the transcript. No checking
  pass, no "Checked up to" divider, no "Checking ..." in the bottom bar.
  Live lines are full ink; only Apple's half-said words are lighter.
- `Transcribe/Transcriber.swift`: a queue of whole files, one at a time,
  run through its own `ParakeetEngine` (same model as live, no new
  download). Audio is fed in 4 s blocks at full speed (FluidAudio's
  streaming manager processes every full window it has, no pacing), words
  go through the same `LineBuilder` as live text. Saved to
  `transcript.json` (model `parakeet-unified-en-0.6b`) every 10 s and at
  the end; `doneUpTo` = end of the last word, so Cancel / crash / Continue
  pick up there. Engine freed when the queue is empty.
- What goes in the queue: imports, "Transcribe again", and recordings
  whose live text is empty or has `Apple` in `engines` (backup engine was
  used). Those start by themselves when Undo Stop expires
  (`recordingFinal`) or on next launch.
- While recording (`growing` not empty) file jobs wait (status line:
  "Starts when you stop recording"). A running job stops after its
  current 4 s block, frees the model, and carries on after Stop. Chosen
  over a second model instance: simpler, and the 8 GB Mac only ever holds
  one Parakeet.
- Ryan's edits to the live text survive a file pass (`WordFilter`): words
  inside deleted live lines (`LiveText.removed`) are dropped, locked live
  lines are put in as he wrote them instead of Parakeet's words there.
- Screen: transcript.json lines (if any), then live lines past `doneUpTo`
  (`TranscriptTools.shownLines`). So during "Transcribe again" the new
  text grows on top of the old live text.
- Model state for files now comes from `LiveTranscriber.modelState`
  (Parakeet). `LiveTranscriber` calls `Transcriber.modelReady()` when the
  download finishes.
- Old Whisper recordings: their `transcript.json` still opens and shows.
  An unfinished one carries on with Parakeet.
- Launch cleanup: everything in `App Support/Verbatim/Models` except
  `Live/` (Parakeet) is deleted, so the 626 MB Whisper model is gone. The
  old `modelFolder` / `modelPrepared` UserDefaults keys are removed.
- Removed: WhisperKit (Package.swift), `WhisperEngine.swift`,
  `ChunkMerge.swift` (with `TextCheck`), chunk cutting and quiet points,
  Low Power Mode wait, the start screen's second model line.
- Start screen: one line, "Speech model ready" / "Downloading the speech
  model".
- Later, only if Ryan finds files worse than live: FluidAudio's
  `UnifiedAsrManager` (batch, full-attention 15 s encoder, same checkpoint)
  is a bit more accurate for files but needs an extra encoder download.
- Step 8 notes: no Whisper prompt any more. Names via FluidAudio vocabulary
  boosting (Ryan said yes to the extra download, 2026-11-10). Checked in
  FluidAudio 0.18.0: `StreamingUnifiedAsrManager.configureVocabularyBoosting`
  (works live, not only on files) with `CustomVocabularyContext` + a
  separate Parakeet CTC 110M model (`Repo.parakeetCtc110m`, ~97.5 MB
  download, ~64 MB extra memory). See FluidAudio
  `Documentation/ASR/CustomVocabulary.md`. Configure it in `ParakeetEngine`
  so live and files both get it. Plus find/replace fix rules. Words screen.

## Step 5c test list for Ryan
1. Update. Start screen shows only one model line ("Speech model ready").
2. Record a lecture video for a few minutes: text is black right away, no
   "Checked up to" line, nothing changes after Stop.
3. Drop a long Voice Memo: done in about a minute or two for an hour.
   Status line shows minutes and time left.
4. Start recording while a Voice Memo is transcribing: the memo pauses
   ("Starts when you stop recording"), and finishes after you stop.
5. More > Transcribe again on a recording where you edited and deleted a
   line: your edit and the deletion stay.
6. Finder > Go > Go to Folder > `~/Library/Application Support/Verbatim/Models`:
   only a `Live` folder left (the 626 MB Whisper model is gone).
7. Old transcripts made with Whisper still open.

## Ryan's feedback: the app feels empty (2026-11-10)
Ryan: "Claude is a simple app but it feels well fleshed out, small things
add up." Settings feels tiny, no "delete all" button. Wants that polish.
Plan: a dedicated chat that does steps 9 (Storage: Recently deleted,
delete all, storage screen) and 10 (Polish: fuller Settings, first-launch
screen, menu bar, small touches) with the ux-planner skill. Start by
listing small touches and showing Ryan a mockup before building.

## Open questions
- Is Parakeet's live text good enough in a real class? Is 2 s delay OK?
- Does Apple's engine need the Speech Recognition permission at all?
  (We ask only when it's actually used.)
- Is Parakeet on files as good as live? (Same model; it should be.)
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
  Int16 (what Parakeet wants), ~115 MB per hour. `Audio/AudioPipeline.swift`.
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

## How importing works (step 3)
(Step 3 used Whisper for the text; step 5c replaced that, see above.)
- Import: drop a file on the window or Cmd+O. `AudioImport` converts it
  to our WAV with AVAssetReader, original untouched. Imports show time
  since start in the gutter, recordings show clock time (pauses skipped).
- Transcript view: status line on top, time gutter, Copy all (Shift+Cmd+C,
  plain text, no speakers yet), More menu (Play audio, Show in Finder,
  Transcribe again, Move to Trash).

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
- Failures are never silent (Ryan saw "nothing" once): any failed check,
  even automatic, says "Update didn't work: <reason>" in the bottom bar,
  and Settings > Updates shows the reason (rate limit, GitHub error,
  signature check failed). Cause of that first silent failure unknown.
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
- Top: "+ New recording ⌘N", like New chat in Claude. Opens the start
  screen; recording begins from its Start recording button (⌘R still
  starts/stops directly). Ryan's ask in step 2b: it used to start at once.
  While recording it reads "Recording now" and jumps to it.
- Bottom: "Transcribe a file…" (same as Cmd+O / drag and drop).
- Updater says "Updated to version X" once after an update.

## How live text works (step 4)
- Engine: NVIDIA Parakeet Unified 0.6B (English, punctuation, ~2 s behind
  speech, int8 encoder on the Neural Engine) through FluidAudio 0.18.0
  (`exact:`, `traits: []` so its TTS/diarizer/text-normaliser parts are left
  out). Only `Live/ParakeetEngine.swift` imports FluidAudio.
- Download: ~600 MB to `App Support/Verbatim/Models/Live/parakeet-unified-en-0.6b-coreml`,
  starts on first launch, resumes, Pause, auto
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
  runner counts samples), so they line up with file transcription.
- Memory: Parakeet loaded at the first audio, unloaded after Stop. If no engine can listen, it looks again
  every 15 s of audio.
- Lines: `LineBuilder` joins words; new line after a sentence end (70+
  chars), a pause over 1.6 s, or 260 chars.
- Saved to `Recordings/<id>/live.json` (formatVersion 1) every 10 s and at
  Pause/Stop. Undo Stop keeps adding to it.
- Screen: live lines in full ink (grey before 5c); status line on top only when Apple's
  engine or nothing is listening. Auto-scroll only at the bottom, else
  "Jump to live". Copy all works while recording.

## Editing lines (pulled forward from step 6, Ryan's ask while testing step 4)
- Click a line (one click, Ryan's ask; was double-click): inline field.
  Text cursor shows over lines. Enter saves, Esc cancels, clicking away
  saves, emptying it deletes. Right-click: Copy this line, Copy from here
  down, Edit line, Delete line, Unlock.
- Works on live lines and file transcription lines, while recording and after.
- Edited lines get `locked: true`, turn full ink, show a lock (click to
  unlock). New live words never go into a line being edited or locked.
- "Line edited. Undo" / "Deleted a line. Undo" in the bottom bar for 10 s.
- Lines are found by their start time (`Model/LineEdits.swift`).
- Transcriber re-reads the lines on screen before adding each batch of words, so
  edits made while it transcribes are kept. "Transcribe again" still
  throws edits away (explicit action).
- Text in lines is no longer selectable outside edit mode (a click
  would select text instead of editing). Copy this line / Copy from here
  down / edit mode cover copying part of it.

## Step 4 test list for Ryan
1. Start screen: "Downloading live text model" line with %, Pause works.
   Then "Getting live text ready", then "Live text ready".
2. Record yourself reading something aloud: text appears ~2 s behind, in
   with punctuation. Names? (Nyankupon, Anansi, Kweku Tsin)
3. Scroll up while it records: it stops following, "Jump to live" shows.
4. Pause, Resume: last words before Pause show up, carries on fine.
5. Copy all while recording, paste into Claude.
6. Stop: live text stays as it is.
7. Activity Monitor > Memory: how much Verbatim uses while recording.
8. If you record before Parakeet finishes: a line says it's using the
   Mac's built-in engine. Does that text look OK?
9. While recording, click a line, fix a word, press Enter: lock
   shows, new words keep coming below. Undo in the bottom bar works.
10. Right-click a line > Delete line, then Undo.

## Background accurate pass (step 5, removed in 5c)
Whisper checked 5 min chunks during class and merged them with the live
text. In Ryan's two lecture tests it skipped sentences, doubled lines and
made text up, and read worse than Parakeet's live text, so step 5c removed
it. Details are in git history (`ChunkMerge.swift`, PLAN.md before 5c).

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
- Start screen animation (Ryan: it stopped abruptly): speech eases in and
  out, pauses at commas and full stops, words hold then fade, then repeat. Live text 62% ink, half-said
  words 45%.
- App icon: not yet. First try (waveform bars + text lines, drawn with
  Pillow) was rejected by Ryan. Next time show a few options first; to
  add one, put `AppIcon.icns` in `Support/`, copy it in
  `scripts/build-app.sh`, and set `CFBundleIconFile` in Info.plist.

## How transcript tools work (step 6)
- `Model/TranscriptTools.swift`: `shownLines(id)` = checked lines + live
  lines not checked yet (what the screen shows, minus half-said words).
  Copy, export and search all use it.
- Copy: ink split button in the toolbar (`CopyButton`), arrow menu has
  Copy all, Copy new since last copy, Copy last 10 minutes. Also in the
  Transcript menu: ⇧⌘C, ⌥⌘C. Button says "Copied 58 lines" /
  "Nothing new since last copy" for 1.8 s (`copyFeedback`).
- Copy new: `RecordingInfo.copiedUpTo` (saved in recording.json) = end of
  the last copied line, from any copy. Copy new takes lines whose middle
  is after it, so it still works after "Transcribe again" reshapes lines.
- Text format: one line per transcript line, no speakers yet (step 7 adds
  `[Mr. Yurt]: "text"`). Settings > General "Include times when copying
  and exporting" (default off) puts `[10:42] ` in front.
- Export: toolbar Export menu or Transcript menu (⇧⌘E = .txt). Save panel
  opens in the last export folder (Documents first time) with a name that
  isn't taken: `2026-11-10 English.md`, else `(2)`. Markdown has a blank
  line between lines. Then "Saved X. Show in Finder" in the bottom bar.
- Search: `.searchable` in the toolbar, ⌘F focuses it (Edit menu's
  text-editing group replaced with Find / Find Next ⌘G / Find Previous ⇧⌘G).
  Ignores case and accents. Hits yellow, current hit stronger
  (`Theme.highlight`), scrolls to it. "2 of 7" line with arrows and Done
  under the toolbar. Enter = next. While searching, live text stops
  auto-following. Cleared when picking another recording.
- Times: Settings > General, clock time (default) or time since start.
  Imported files always use time since start.

## Step 6 test list for Ryan
1. Open a transcript, press ⌘F, type a name: yellow hits, "1 of N",
   Enter and the arrows move between them, Done clears it.
2. Copy all, paste into Claude. Then record or wait for more text, use the
   arrow next to Copy all > Copy new since last copy: only the new part.
   Press it again right away: "Nothing new since last copy".
3. Copy last 10 minutes on a long transcript.
4. Export > Markdown, save, open the file. Export again: the name gets (2).
5. Settings > General: switch to Time since start; times in the left
   column change. Turn on Include times, copy, paste: [10:42] in front.
6. Does the ink Copy button with the arrow look right in light and dark?

## Step 2b test list for Ryan
1. Update, open an old transcript: serif text, warm white, ink Copy all.
2. Switch the Mac to dark mode (System Settings > Appearance): still
   easy to read? Copy all turns light.
3. Record a minute: live text readable?
4. Anything that looks off or cramped: tell Claude in plain words.
