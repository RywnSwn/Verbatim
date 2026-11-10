# Plan

Status (2026-11-09, fifth chat): steps 1, 2, 2b, 3, 4, 5, 6 and 11 merged
into `main`. Step 6 merged before testing (Ryan tests through the in-app
update): ask him to run the "Step 6 test list" below. Step 2b merged (Ryan asked to merge before testing; its test
list is below). Step 5 is still not tested
by Ryan: ask him to run the "Step 5 test list" below. Also still
unanswered: line editing on a real Mac, step 3 accuracy on a real class
Voice Memo.
Step 5c (drop Whisper) merged 2026-11-10 (RywnSwn/Verbatim#12) at Ryan's
ask, with the audio shrink after Stop. Not fully tested yet: ask Ryan for
the "Step 5c test list" and the audio shrink test. App icon later.
Step 7 (speaker labels) merged 2026-11-10 (RywnSwn/Verbatim#13) before
testing, at Ryan's ask: ask him for the "Step 7 test list". Next: step 7b
(markers) in a new chat.
(Another chat had also built 5c, RywnSwn/Verbatim#11; Ryan closed it. Its
branch `claude/step-5c-parakeet-only` couldn't be deleted from the
container; Ryan can delete it on GitHub.)
Fix on 2026-11-10 (sixth chat): Play audio now plays in the app (it opened
Apple Music and was "broken"), plus Delete Audio Only. Ryan: Parakeet is
"pretty good". Not tested by Ryan yet: see "In-app player test list".
Fix on 2026-11-10: accurate pass was dropping sentences (prompt too long,
see step 5 notes). Ask Ryan to record the same kind of lecture again and
compare live vs checked text. Second test (Transcribe again): no more
missing sentences, but doubled lines and made-up text; fixed the same day.
Markers are step 7b and voice memory is step 7c (Ryan, 2026-11-10), both
after he tests step 7.
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
6. [x] **Transcript tools.** Timestamps, (edit + lock done in step 4), Copy / Copy new,
       export .txt/.md, search. Merged, not tested by Ryan yet.
5c. [x] **Drop Whisper, Parakeet only** (Ryan's call, 2026-11-10). See
       "Plan for step 5c" below.
7. [x] **Speaker labels.** Speaker 1, 2..., rename once, click to fix.
       Merged, not tested by Ryan yet (see "How speaker labels work").
7b. [ ] **Markers** (Ryan said yes, 2026-11-10). ⌘D while recording or
       right-click a line > Add marker here (also after class). Flag next to
       the time. Copy and export put "⚑ " in front of marked lines. "Copy
       marked parts only". Undo in the bottom bar.
7c. [ ] **Voice memory** (Ryan's ask, 2026-11-10). Remember a voice once
       Ryan names it, so next time "Mr. Yurt" is named by itself. Sortformer
       can enroll saved voice audio (`enrollSpeaker`); check FluidAudio's
       docs on how well it maps. Needs a "Voices" list to rename or forget.
8. [ ] **Corrections memory.** Word list via Parakeet vocabulary boosting
       (~100 MB extra download, Ryan said yes), fix rules, Words screen.
9. [ ] **Storage.** History sidebar, 7-day audio delete, Storage screen,
       Recently deleted, Export everything.
10. [ ] **Polish.** First-launch screen, menu bar dropdown, Settings, notifications,
        all the edge cases in `docs/spec.md` that aren't done yet.
11. [x] **Updates.** In-app update button (own updater, not Sparkle).

## Nice to have (after the above)
- [x] Timeline: click a line's time to hear that bit of audio (clicking the text edits it). Done with the in-app player.
- [ ] Engine comparison screen for live engines.
- [ ] Auto-name recordings from what was said (Ryan's ask), e.g.
      "English: Anansi and the sky god", with Apple's on-device
      Foundation Models (offline, free). Needs Apple Intelligence on.
      Ryan can still rename.

## Plan for step 5c: drop Whisper (built, see "How step 5c works")
Why: in Ryan's two lecture tests Whisper skipped sentences, doubled lines
and made text up ("I'm not a vampire" x15), even after fixes. Parakeet's
live text was better. FluidAudio's own benchmark (LibriSpeech test-clean):
Parakeet Unified streaming 2.21% avg WER, batch 2.16%, so the live text is
already about as accurate as it gets, and RNNT can't invent sentences.
What to build:
- Recordings: the live text IS the transcript. No checking pass, no
  "Checked up to" divider, no "Checking 10:40 to 10:45", live lines full
  ink once final (half-said words can stay lighter). Edits/locks/deletes
  keep working as they do on live lines.
- Imports and "Transcribe again": run Parakeet over the WAV (feed the
  existing streaming engine at full speed, ~66x real time per FluidAudio,
  so a 1 h class in about a minute). Same model, no new download. Decide
  whether an import waits while recording (one model in memory, 8 GB Mac)
  or uses a second instance; waiting is simpler.
- Recordings made with Apple's backup engine (Parakeet wasn't ready):
  offer/auto "Transcribe again" with Parakeet after Stop.
- Remove WhisperKit (Package.swift), `WhisperEngine.swift`, the Whisper
  download/prepare lines on the start screen, `ChunkMerge` / `TextCheck`
  and the 5 min chunk logic in `Transcriber`. Keep the queue idea for files.
- On launch, delete the old Whisper model folder (626 MB) in
  App Support/Verbatim/Models once, so Ryan gets the space back.
- Old recordings with a Whisper transcript.json still open and show it.
- Step 8 changes: no Whisper prompt any more. Ryan wants the extra
  download for names (2026-11-10): FluidAudio vocabulary boosting. Checked
  in FluidAudio 0.18.0: `StreamingUnifiedAsrManager.configureVocabularyBoosting`
  (works live, not only on files) with `CustomVocabularyContext` + a
  separate Parakeet CTC 110M model (`Repo.parakeetCtc110m`, ~97.5 MB
  download, ~64 MB extra memory). See FluidAudio
  `Documentation/ASR/CustomVocabulary.md`. Plus find/replace fix rules for
  anything it still misses. Words screen as planned.
- Spec and design docs: remove "accurate pass" parts.
- Save real word times (Parakeet gives token timings) on each line, e.g.
  `Transcript.Line.words: [start]` or similar, dropped when Ryan edits the
  line. The player's word highlight (`TranscriptList.wordHighlighted`)
  estimates by word length today; switch it to real times when present.
- Optional later: FluidAudio's `UnifiedAsrManager` (batch, full-attention
  15 s encoder, same checkpoint) is a bit more accurate for files but needs
  an extra encoder download. Not worth it unless Ryan finds files worse.
Test list for Ryan: record a lecture video, text is final right away and
stays the same after Stop; import a Voice Memo, done in about a minute;
Settings/start screen no longer mention a second model; disk space back.

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
- Is large-v3 turbo (626 MB) fast enough on Ryan's M2? Test in step 3.
- Speaker labels in a real class: is the teacher always Speaker 1? Do quiet
  students far from the Mac get missed (Sortformer's known weak spot)?
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
- Prompt: the last 3 checked lines (max 150 chars, 32 tokens) go to
  Whisper as context. Was 120 tokens: WhisperKit's decoder holds only 224
  tokens per 30 s window including the prompt, so fast speech got cut off
  and the rest of the window skipped (Ryan's first real test, a history
  lecture: whole sentences missing, accurate text worse than live). Step 8's
  word list must fit in this small budget too.
- Clean-up (`ChunkMerge.cleaned`, `TextCheck`, compares word pairs): drops
  Whisper segments that loop ("I'm not a vampire" x8), the start of a
  segment that repeats the end of the one before, segments that mostly
  repeat the two before, and segments with almost nothing in common with
  the live text around them (made up). Then a live line whose word pairs
  are mostly missing from Whisper's text within 20 s is kept as it is
  (`ChunkMerge.skipped`). By text, not time: the first version compared
  times and doubled lines in Ryan's second test. Segments that just repeat the prompt are dropped.
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
- "Checked up to" divider in serif italic.
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
  is after it, so it still works after the accurate pass reshapes lines.
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
3. Record a minute: live grey text readable? "Checked up to" line looks OK?
4. Anything that looks off or cramped: tell Claude in plain words.

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

## How step 5c works (Parakeet only)
- `live.json` (`LiveText`) is the transcript. Recordings made with Parakeet
  need nothing after Stop. All lines full ink; only Apple's half-said words
  are lighter.
- `Transcribe/Transcriber.swift` (rewritten): a queue of files. Each job
  feeds the WAV to its own `ParakeetEngine` in 30 s pieces at full speed,
  adding words to live.json through `LiveTranscriber.addPass`. Progress in
  `LiveText.pass` (`doneUpTo`, `finished`, `stoppedByUser`), saved after
  every piece; after a crash it carries on from the last word saved.
- Files wait while a recording is going (`growing`): a running job flushes
  its words and stops at the end of its piece, then carries on after the
  recording is final (Undo Stop expired). Status line: "Waits until you
  stop recording".
- Used for: imports, "Transcribe again", recordings with no live text, and
  recordings made with Apple's backup engine (redone by themselves after
  Stop if Parakeet is ready; otherwise "Redo with Parakeet" link).
- "Transcribe again" keeps edits: locked lines go into `pass.keep` and are
  put back in place as the pass gets there (Parakeet's words inside them
  are dropped); `removed` spans stay removed.
- Word times: `Transcript.Line.words` = start of each word (0.01 s), made
  by `LineBuilder`. The player uses them; edits clear them.
- Old recordings: a Whisper `transcript.json` still shows (as "checked"
  lines, then live lines after its end under "Old transcript ends at").
  An unfinished one with no live text gets "Continue", which runs
  Parakeet from where Whisper stopped.
- Whisper model folder: everything in App Support/Verbatim/Models except
  `Live` is deleted once on launch (`whisperModelRemoved` flag).
- Start screen: one "speech model" line (was two).

## Step 5c test list for Ryan
1. After updating: start screen shows one "Speech model ready" line, no
   "accurate model". Finder > App Support/Verbatim/Models: only `Live` left.
2. Record a few minutes (a lecture video is fine): text is black right
   away, no "Checked up to", nothing changes after Stop.
3. Drop a Voice Memo: "Transcribing ... min left", done in about a minute
   per hour of audio. Cancel halfway, then Continue.
4. Import a file, then start recording before it finishes: the file says
   it waits, then finishes after you stop.
5. Play audio on a new recording: the blue mark sits on the exact word.
6. Edit a line, then More > Transcribe again: your edit is still there.
7. Old recordings still open and look the same.

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
