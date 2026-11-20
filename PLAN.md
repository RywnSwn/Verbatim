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
testing, at Ryan's ask: ask him for the "Step 7 test list". Step 7b
(markers) built the same day in the same chat (Ryan's ask): see "How markers
work". Step 7c (voice memory) built in the same chat too: see "How voice
memory works". 7b and 7c merged 2026-11-10 (RywnSwn/Verbatim#14, #15) before
testing, at Ryan's ask: ask him for the 7, 7b and 7c test lists. Step 8 (word list) merged 2026-11-11 (RywnSwn/Verbatim#16) before testing, at Ryan's ask: ask him for the "Step 8 test list". Step 9 built in the same chat and merged before testing (RywnSwn/Verbatim#17), at Ryan's ask: ask him for the "Step 9 test list". Step 10 (polish) merged 2026-11-12 (RywnSwn/Verbatim#18) after Ryan approved mockup v3 (https://claude.ai/artifact/2ii2Hd8QkNtZ6gtxUYHziJ): see "How step 10 works" and its test list.
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
Markers are step 7b (built) and voice memory is step 7c (Ryan, 2026-11-10).
Fix on 2026-11-12 (branch `claude/fix-stutter-sidebar-sizing`, which has
`claude/step-10-polish` merged into it, RywnSwn/Verbatim#19): Ryan reported
"so many glitches" in the step 10 test builds (sizing, stuttering, the
sidebar) and asked about moving to Tauri. Found and fixed in code: the menu
bar and the whole sidebar were redrawn 20 times a second while recording
(they read `model.elapsed`), and the whole transcript was redone 8 times a
second while audio played (it read `Playback.time`, and every visible line
searched all lines). Rule from now on: a view that reads `elapsed`,
`levels` or `Playback.time` must be a tiny view of its own. Also
`DetailView` now sits in a `GeometryReader`, so a main-area screen that
wants more height than the window can't stretch the split view and push
the sidebar's top and bottom outside the window (Ryan saw that). Keep it.
Mistake to avoid: this chat first branched from `main` when step 10 was
still on its own branch, and Ryan got a test build with the old design.
Check `git branch -r` for unmerged work before starting. Not tested by Ryan yet. Ask him for
a glitch list (what he did, what he saw). Tauri: see `DECISIONS.md`, not
decided by Ryan yet.
Same day: 0.1.102 crashed for Ryan when he clicked the sidebar button
(AppKit "too many Update Constraints passes" from the split view, same
family as the 0.1.98 crash). Could NOT be reproduced on the CI Mac, but
the test showed the system sidebar button did nothing below about 745 pt
wide (no room). Fix in 0.1.109: our own sidebar button
(`ContentView.toggleSidebar`, ⌃⌘S, system one removed); a window narrower
than 860 pt is widened first, then the sidebar opens. Sidebar footer got a
solid background (rows showed through the text). Not confirmed by Ryan yet;
he was asked whether the window was narrow (sidebar hidden) or wide when it
crashed. If it still crashes, get the new crash report and that answer.
NEW, use it: `.github/workflows/smoke.yml` + `scripts/ci-smoke.sh` run the
app on the CI Mac for every push to a `claude/**` branch, with fake
recordings and groups, resize the window, press ⌃⌘S, and push screenshots
to the `ci-smoke` branch (`git fetch origin ci-smoke`, then look at the
PNGs). Claude can see the real app this way. Look at the screenshots before
giving Ryan a build. Known gap: clicking a sidebar row in the script does
not open a recording yet, so only the start screen is covered.
Same day, the real cause of "sidebar top and bottom outside the window"
(found with Ryan's Help > Copy Layout Details output, 0.1.115):
NavigationSplitView made itself as tall as its columns WANTED (title bar +
start screen content + bottom bar = 692 pt) instead of the window (552 pt).
Fix in 0.1.117: both columns get `.frame(minHeight: 0, idealHeight: 300,
maxHeight: .infinity)` in `ContentView` (keep these). The smoke test now
fails if the split view's height differs from the window's. Help > Copy
Layout Details (⌃⌘L, `Views/LayoutDetails.swift`) stays: ask Ryan for it
whenever something is in the wrong place. His menu bar hides Help behind
the notch, so tell him the shortcut. Ryan confirmed it ("finally") and asked to merge: step 10 and these fixes
are on `main` since 2026-11-12 (RywnSwn/Verbatim#19 into #18 into main).

Lag while recording (2026-11-12, branch `claude/fix-recording-lag`, not
tested by Ryan yet, not merged): Ryan said recording lags and that it
defeats the point (fixing lines live). Found in code, could not be measured
(no Mac here):
1. `RecordingHeader` read `model.elapsed`, so 20 times a second the header
   counted every word of the transcript ("X and Y spoke"). Slower the longer
   the class ran. Now the ticking line is its own view, `HeaderMeta`.
2. Typing in a line being edited changed `@State draft` of `TranscriptList`,
   so every key press redrew the whole transcript. Now `LineEditor` keeps
   its own text and writes it to a plain box (`LineDraft`) that the list
   reads when saving.
3. Each row of the transcript's `ForEach` now makes exactly one view (a
   `VStack`). With a different number per row, the lazy stack builds every
   row on each change. Keep it one view per row.
4. `MiniView` read `elapsed` and `levels`; that part is now `MiniClock`.
Not touched: `MenuBarLabel` still redraws 20 times a second (it draws the
moving bars in the menu bar). If Ryan still sees lag, ask WHICH lag: words
showing up late after they're said (Parakeet is about 2 s behind by design),
the app stuttering, or typing being slow, and whether it gets worse the
longer the recording runs. Then look at `MenuBarLabel` and at
`LiveTranscriber.apply` (it changes `texts`, which every transcript view
reads) and the pretty-printed live.json save every 10 s on the main thread.

Mini window goals (Ryan, 2026-11-12, with a screenshot of the idle mini
window; nothing built yet, mockup first with the ux-planner skill):
1. It looks bare, most of all when not recording (just "Not recording" and
   two icons). Give it a real design.
2. A close button inside it.
3. A weird empty margin at the top, recording or not. Likely cause: the
   panel has a hidden title bar (`.titled` + `.fullSizeContentView`) and
   the SwiftUI content stays out of the title bar's safe area. Try
   `.ignoresSafeArea()` on `MiniView`, or a borderless panel, and add the
   mini window to the smoke test screenshots to check.
4. Text can be edited in the mini window too. Open question Ryan raised:
   what happens when new words come in while he is still editing. In the
   big window the edited line is locked and new words start a new line
   (`LiveTranscriber.editing`); the mini window shows only the last 2
   lines, so decide what it shows while one is being edited (for example:
   the edited line stays put and new lines keep coming under it).

Merged together (2026-11-12, Ryan's ask): `claude/mini-window-redesign` now
holds the lag fix + the mini window + `claude/design-pass` (another chat's
work: sidebar rows, drag, glass or solid, Settings pages, speaker model off
the GPU, forget speaker names). Test builds from this branch have all of
it. Only `scripts/ci-smoke.sh` clashed (both parts kept). Not merged into
`main` yet: Ryan tests first.
Lag came back (Ryan, 2026-11-12 evening, after the design pass was merged
in): the one live-audio difference between the builds that felt fine
(0.1.135, 137: lag fix only) and the ones that lagged (139+) is
`SpeakerEngine.computeUnits = .cpuAndNeuralEngine` from the design pass
chat. Put back to `.all` (FluidAudio's default). Not confirmed by Ryan yet.
⌃⌘L now also says "LIVE TEXT BEHIND THE MIC: X s now, worst Y s"
(`LiveFeed.behind`): audio waiting for the models. If that grows while
recording, the models are too slow (not the drawing). If lag is still
there, get that paste before changing anything else.
What the lag really is (Ryan, 2026-11-12, on 0.1.141): "it's just stopped
basically; I pause it, the words appear and the timer updates". His ⌃⌘L
paste: while recording 47 checks all fast, then one check that took 151 s
and only came back after Pause (it was counted under "not recording", fixed
now). So a few seconds into a recording the MAIN THREAD stops running its
queue (timer, bars and text all arrive through it) until capture stops.
Not the header, not typing. Cause still unknown. From 0.1.146 the meter
runs `/usr/bin/sample` on Verbatim when the main thread has been stuck
1.5 s during a recording and ⌃⌘L pastes the main thread's stack ("STALL
SAMPLE") plus the longest gap between audio buffers ("MIC"). NEXT STEP:
get that paste from Ryan and read the stack. Do not guess again.
Second and third pastes (0.1.146): mic fine (no gaps), live text 14 s
behind then 0 after Stop, main thread answering only every 1 to 5 s while
recording, CPU idle in the sample (threads waiting, not computing). Ryan:
all text flies in on Pause or Stop, the rest of the app is fine, memory is
not it. Reading: the main thread is jammed while audio is captured, and
LiveRunner needs about 7 main-thread hops before the first word, so text
waits too. Suspect (NOT confirmed): `MenuBarLabel` was fed `levels` and
`elapsed` 20 times a second; a menu bar item is drawn outside the app, so
each change is a round trip to macOS. 0.1.148 feeds it `menuBars` and
`menuClock` (2 changes a second at most). 0.1.148 also prints the main
thread's stack from the saved sample (`Diagnostics/stall.txt`), even after
a relaunch: get that paste to confirm or kill this suspect.
CAUSE FOUND (stall sample from 0.1.146, pasted on 0.1.148; the menu bar
change did not help): 70% of the main thread's time was in
`CA::Transaction::commit > -[RBLayer display] >
RB::SharedSurfaceGroup::add_subsurface > wait_for_allocations >
-[CAContext waitForCommitId:timeout:] > mach_msg`. So SwiftUI's renderer
(RenderBox, macOS 26) blocks the main thread inside a commit, waiting for
the screen to show earlier drawing before it hands out another drawing
surface. Ryan also saw it run smoothly for a moment whenever something
else redrew the window (⌃⌘L's message bar). What made so many surfaces:
`Waveform` was 40 shapes switching between Circle and Capsule 20 times a
second, the timers had `.contentTransition(.numericText())` with an
animation every second, the sidebar's live row had a repeating
`.symbolEffect`. 0.1.149: Waveform is one Canvas, no rolling digits, no
repeating symbol effect. NOT confirmed by Ryan yet. If it still freezes:
get a new sample (⌃⌘L after a freeze) and look at what is under
`-[RBLayer display]`; next things to try: `.drawingGroup()` on the bottom
bar, fewer text updates (timer once a second), the transcript's scroll
animation.
Lag numbers: `Model/HitchMeter.swift` checks ten times a second how long
the main thread takes to answer. ⌃⌘L (Copy Layout Details) now ends with
"MAIN THREAD ... while recording: N checks, N slower than 0.1 s, worst
X s". If Ryan still sees lag: have him record a few minutes, press ⌃⌘L and
paste. Many slow checks = the app's own drawing is the problem (look at
views). Few or none while it still feels laggy = it's the models or
memory (word spotter, 8 GB), not the drawing.

Mini window redesign BUILT (2026-11-12, branch `claude/mini-window-redesign`,
which sits on top of `claude/fix-recording-lag`; test build 0.1.137; not
merged, not tested by Ryan). Ryan said "get to work" on the mockup and
asked for icons on the links (Undo, Undo Stop, Copy all have one now).
Checked on the CI Mac: it builds and the idle look matches the mockup with
no gap on top (smoke screenshot `07-mini-idle.png`). NOT checked anywhere
(the CI Mac can't record): the recording look, and typing in a line. The
risky part is the keyboard: the panel is borderless + non-activating,
`MiniPanel.canBecomeKey` is true and `MiniLines.begin` calls
`MiniWindow.takeKeyboard()` before focusing. If Ryan can't type in a line,
look there first. Mini window test list:
1. ⇧⌘M when not recording: no empty strip on top, "Ready to record", Start
   button, last recording with Copy all.
2. Start from it. Bars, timer and name on top; 3 lines of text; words under
   each button.
3. Click a line, change a word, Enter. "Line edited. Undo" with an icon.
   Try Esc too, and clicking another app while typing (should save).
4. While typing, keep audio playing: your line stays still, new lines come
   under it, then "N more new lines below".
5. × while recording: window goes, menu bar timer keeps counting. ⇧⌘M
   brings it back.
6. Stop: "Undo Stop" with an icon, then the idle look. Drag the window
   somewhere, close and reopen: same spot.

Mini window mockup (2026-11-12, approved by Ryan: "get to work"):
https://claude.ai/artifact/Rb3GkVcczc7apbQsvJjfnD, copy in
`docs/design/MiniWindow.html`. What it shows:
- No title bar at all (borderless rounded panel), so no gap on top. Top row:
  × (left, hides the window only, recording keeps going), bars, timer,
  recording name, back-to-big-window button.
- Recording: last 3 lines (was 2). Click a line to edit it in place: Enter
  saves, Esc cancels, clicking away saves, "Line fixed. Undo" in the
  message strip. While editing, that line stays on top and still; new words
  start a new line below (same rule as the big window); at most 2 newer
  lines show, then "N more new lines below. Save to see them."
- Buttons have a small word under each icon: Copy new, Marker, Pause, Stop.
- Not recording: "Ready to record", mic and group, an ink Start recording
  button, the last recording with Copy all. After Stop: "Stopped and saved,
  12 min. Undo Stop".
- Closed while recording: the menu bar timer shows it's still going; the
  menu bar icon or ⇧⌘M brings it back.
Build notes: the panel must be able to take the keyboard for typing
(`becomesKeyOnlyIfNeeded` is already on). Reuse `LineEditor` and
`LiveTranscriber.editing` from the big window. Add the mini window to the
smoke test screenshots.

Ryan's asks on 2026-11-12 for the NEXT chat (design pass, mockup first,
use the ux-planner skill; nothing built yet):
1. Sidebar can be opaque: a Settings choice, glass or solid.
2. Recordings in the sidebar are hard to tell apart. Ryan (asked, same
   day): "a little light boxing" on each row, a light tint when the pointer
   hovers a row, and the recording whose transcript is open is highlighted.
3. Dragging a recording should feel like holding it: the row lifts and
   follows the pointer, a move, no green plus badge (the plus is macOS
   saying "copy").
4. Settings has more in it now and should get a nicer design.
Behaviour and edge cases: `docs/spec.md`. Layout to build to:
`docs/design/README.md`.

Design pass mockup (2026-11-12, approved by Ryan, BUILT on branch
`claude/design-pass`, not tested by Ryan yet, see "How the design pass works"):
https://claude.ai/artifact/52gonTfcK3E7cSGNCY78tg, copy in
`docs/design/DesignPass.html`. What it shows:
- Rows: each recording on its own borderless box, 3 pt apart. Two styles,
  and Ryan wants BOTH as a choice in Settings > Look ("Recordings"):
  "Soft boxes" (default: ink tint 4.5%, hover 8.5%, open 15% + bolder
  name) or "Paper cards" (white cards with a faint shadow, open card ink).
- Glass or Solid sidebar: new choice in Settings > Look. Reduce
  transparency on = always solid.
- Drag: row lifts (scale 1.05, tilt 1.6 degrees, shadow), gap stays where
  it was, the group under the pointer tints and says "Move here", a folded
  group opens after 0.65 s, Esc puts it back, drop shows "Moved to X. Undo"
  in the bottom bar. Plan for the build: a DropDelegate that proposes
  `.move` (no green plus inside Verbatim), drag preview drawn like the
  lifted row. Out of the app it stays a Markdown file (copy, plus is right).
- Settings: pages down the left (General, Look new, Transcription, Words,
  Voices, Storage, Updates, Shortcuts new) instead of top tabs. Each page:
  title + one line, then filled groups of rows (label and help left,
  control right). Look holds sidebar (glass/solid), recordings (soft
  boxes/paper cards), text size, times, times in copies.

## Code health review (2026-11-18), checked against what is now main
Done by another chat on main (3 reviewers), then checked in this chat
against this branch. Only the live text delay item is changed here (the
fix is on this branch). Everything else is still true on this branch.
Order to do them in, one chat each:
1. Test the live text fix and new start screen (main build), report back.
2. Quick fixes: DONE 2026-11-18, merged (RywnSwn/Verbatim#22, not
   tested by Ryan yet, see "Quick fixes test list" below). Was:
   - Stop, then start a new recording within 10 s: `start()` clears
     `stoppedNote`, so the old one never gets `Transcriber.recordingFinal`
     / `AutoName.consider`: background work stalls until relaunch
     (`RecorderModel.swift` stop() and start()). Confirmed on branch.
   - Audio shrink: a crash mid-shrink leaves a leftover file and it never
     shrinks again, retries every launch.
   - Uninstall doesn't remove the "verbatim" entry from Claude's config.
   - Export Everything leaves out groups.
   - Connect to Claude: if the config exists but can't be read, Connect
     could overwrite Claude's other servers.
   - Mini window, menu bar panel and bottom bar redraw everything 20x a
     second while recording: move the clock into tiny views.
   - Every live word redraws most of the window: `LiveTranscriber.apply`
     writes the observed `texts` dictionary (`texts[id] = t`).
   - New (this branch): start page title menu > New Group… uses the
     rename alert on `SidebarView`; with the sidebar hidden (narrow
     window) the prompt may not show. Move the alert up to ContentView.
3. Protect data: DONE 2026-11-19, tested by Ryan and merged
   (RywnSwn/Verbatim#25, see "Protect data" at the end). Was: "Stop and
   Quit" lost up to 10 s of live text; a failed save was silently undone
   on the next app activation; live and file Parakeet could be loaded at
   once.
4. Errors: a speech model error is swallowed, the app keeps saying
   "listening". Turn the HitchMeter off once the lag is solved.
5. Tests: none exist. Add a test target that runs on CI. First: word list
   fixes, keeping edits when accurate text arrives, speaker naming, WAV
   writing, reading old saved recordings.
6. Cleanup: RecorderModel split, the ~9 copies of "status for N seconds",
   paths/saving/download copies, Shortcuts page missing ⇧⌘E ⌥⌘P ⌘G,
   speaker counting copied (RecordingHeader + Speakers), Swift 6 mode,
   trim this file (old "how step N works" notes to docs/).
7. Faster start-up: DONE 2026-11-18 (see "Faster start-up" at the end).
   Left over: app activation re-reads every recording.json. (The live
   text save every 10 s is off the main thread now, item 3.)
How the quick fixes were done (2026-11-18):
- `RecorderModel.finishStopped()` ends Undo Stop for good (recordingFinal +
  AutoName). Called by the 10 s timer, by `start()` and when Undo Stop fails.
- `AudioSquash.squash`: an m4a already there with the WAV still there is
  checked (`isWhole`); whole = delete the WAV, else redo it.
- `Uninstaller.run` calls `ClaudeConnector.disconnect()` when connected.
- Export Everything: `Transcripts/<group name>/...`, Recents at the top,
  plus `Data/groups.json`.
- `ClaudeConnector.readConfig` only treats a MISSING file as empty; one it
  can't open throws. Connect also refuses an odd "mcpServers" shape.
- Clocks: `BarClock`/`BarWaveform` (BottomBar), `PanelClock` (MenuBar).
  Mini window and panel Marker buttons use `canMark`, not `markerTarget`
  (that one reads `elapsed`). Rule stands: never read `elapsed`, `levels`
  or `markerTarget` in a big view.
- `LiveTranscriber.texts` is now `LiveTexts` (read only, `texts[id]`), one
  `@Observable LiveBox` per recording; writes go through `put`. Only
  volatile words changing no longer rewrites the lines.
- "Name this group" alert: `GroupNameAlert` in `ContentView.swift`.
Test build 0.1.178 (or newer from this branch). CI build and smoke test
passed, screenshots checked (start screen, mini window, Settings normal).
Quick fixes test list (for Ryan):
1. Record a few seconds, Stop, then start a new recording right away (in
   under 10 s). Stop that too. Both should get their checked text and a
   name, without reopening the app.
2. Make the window narrow (sidebar hides), then on the start page use the
   title menu > New Group…: the "Name this group" box shows.
3. Settings > Storage > Export Everything: the zip has a folder per group.
4. While recording, the app should feel at least as smooth as before.
Live text fix itself (read in this chat): queue + 5 s bites, Parakeet and
speakers load at once (higher peak memory while loading, worth watching
on 8 GB), nothing wrong found, not yet tried on Ryan's Mac.

Review of the merged code (PR 21: live text fix, start screen, AI Apps),
done after the merge, read only, nothing run. No crash or data-loss bugs.
Add to the quick fixes chat (item 2) unless noted:
- Live text start: `LiveRunner.run` waits for `speakersReady` before any
  audio is handled, and `startSpeakers` plays up to 3 known-voice clips,
  so first words still wait for the speaker start even when Parakeet is
  ready first. Let words flow while speakers start (label later lines
  only). Do this after Ryan's test shows the "LIVE TEXT START" numbers.
- Memory: Parakeet, word spotter and Sortformer now load at the same
  moment (`async let` in `LiveRunner.run`). Measure the peak on 8 GB; if
  it swaps, load speakers after Parakeet again (with the queue, the
  backlog now clears fast anyway).
- Undo Stop: `LiveFeed.open()` zeroes `given`/`done` and the start times
  while the old run is still draining and calling `finished()`, so
  "LIVE TEXT BEHIND" and "LIVE TEXT START" are wrong after Undo Stop.
- "Live text is catching up" (`RecordingViews.swift`, LiveStatusLine)
  says "the last few seconds" even when minutes wait. Say how far behind
  it is (`LiveQueue.waitingSeconds`).
- Start page date (`StartView.swift`, titleBlock) is `Date.now` in body:
  left open overnight, it shows yesterday. Redraw when the day changes.
- Cleanup (item 6): `PageModelStatus` copies `LiveModelStatusLine` (same
  file); `LiveQueue.waiting` and `LiveFeed` given/done count the same
  backlog twice (use one); `LiveQueue.take` joins up to 5 s of audio
  while holding the lock the mic needs (swap the array out, join
  outside); the page geometry (70 gutter, 1.5 pt rule, 760 column, 32
  side, 24 top) is copied as numbers in StartView, TranscriptList and
  RecordingHeader (put it in Theme).

## Bugs to fix (Ryan, from real use)
- **Live text is late (2026-11-18, in class).** Words only start to show
  after a few minutes of recording, and it does not feel as live as the
  very first builds (step 4 era, about 2 s behind). Not looked at yet.
  First step next chat: ask Ryan for his ⌃⌘L paste taken while it is
  behind (it has "LIVE TEXT BEHIND THE MIC" and the stall sample), and
  which version he is on. Then compare with the old lag notes below
  (main thread stall, `SpeakerEngine.computeUnits`) before changing code.
  Fix tried the same day, branch `claude/fix-live-text-delay` (Ryan asked
  to try one before a paste). Found in code, not measured: at Start the
  speaker model loaded (and played the known voice clips), THEN Parakeet
  (and the word spotter), before any audio was handled; the audio saved
  meanwhile then went through every model and to the screen one tiny bit
  at a time (the mic gives ~47 bits a second), so the backlog cleared
  slowly. Now: `LiveQueue` (one per run) and `LiveRunner` takes all audio
  waiting at once, up to 5 s per step (`biggestBite`); Parakeet and the
  speaker model load at the same time (`async let`); "Live text is
  catching up" shows above the transcript while 4+ s wait (gone under 1
  s); ⌃⌘L has "LIVE TEXT START": seconds after Start until Parakeet
  listening, speakers listening, first words. If words are still late,
  that line says which part is slow. If "behind" keeps growing after the
  start, the models are slower than speech (look at ANE sharing between
  Parakeet, Sortformer and the word spotter), not the start.

## Next asks from Ryan (2026-11-18): MERGED to main (RywnSwn/Verbatim#21)
`claude/general-names-simpler-start` and `claude/fix-live-text-delay` are in
main, merged at Ryan's ask before his test. Test list below still to do.
Done (not tested by Ryan yet):
1. Gear menu: "Copy Details for a Bug Report" (other choices offered to
   Ryan: "Copy Problem Details", "Copy App Details"). "Connect to Claude"
   in the gear menu is now "Connect to AI Apps".
2. Settings page "Claude" is now "AI Apps". Claude row stays first; new
   "Other AI apps" row with Copy Setup (the `mcpServers` JSON with this
   app's path and `--mcp`, `ClaudeConnector.setupText()`). Wording no
   longer says only Claude. Enum case stays `.claude`.
3. New recording never starts by itself: the "+" on a group and its
   "New Recording Here" call `model.showNewRecording(in:pickGroup:)`,
   which opens the start screen with that group in "Save in". ⌘K "Record
   in" and the menu bar "Record in" still start right away (asked for
   by name there). Found why New recording "didn't work": from Recently
   deleted it set `selection = nil`, but `showingDeleted` stayed true, so
   the screen didn't change. Fixed.
4. Start screen: mockup https://claude.ai/artifact/Bx3y11h4r3KMAz1s9EnCbh
   (A: one white box with "Save in" + Start, like Claude's chat box, mic
   name in one small line, status only while something downloads; A
   first-time state; B: one big round button; and today's for comparison).
   Ryan: A is "too much like chat". Looked at similar apps: Voice Memos
   (no start screen, one red record button always in the same spot),
   Granola and Otter (home is your list of recent notes, record is a
   small button), Apple Notes (record from a toolbar button). Added C
   (a "Today" page: Record top right, last 3 classes in the group below)
   and D (record button docked at the bottom like Voice Memos). Waiting
   for Ryan to pick. Ryan then picked **E, "a blank notebook page"**:
   the group name is the page title (click it to pick another group),
   date and mic under it, Record button on the right of the title line,
   an empty ruled page below ("The class shows up on this page as it's
   said."), footer with last class link and "Or drop a Voice Memo here".
   When recording, the same page fills in (no jump). No greeting, no
   centered box. Button: Verbatim wave icon, no red dot, no black pill.
   Color not final: Ryan likes warm red #B5523F, also looked at
   notebook blue #2F5F9E and plum #6A5A8E. States drawn: E1 ready,
   E2 first time (download + "Make a group" link), E3 recording,
   E4 group menu open. Next: Ryan picks the color, then build it in
   `StartView.swift` (and the recording view's header to match E3).
   Ryan then: "right direction but looks weird", links look weird, what
   about dark mode. Cause: the mockup's sidebar didn't match the real app
   (CI screenshots: dark mode, floating glass sidebar, group icons,
   recording cards). Redrew E in the real look, dark and light, with no
   underlined links (last-class link dropped, Pause is a small button).
   Mockup row "E, in the real app's look". Ryan: no lines on the page
   (removed), Record button in the **Mac's system accent color**
   (`NSColor.controlAccentColor`, not Theme.accent). Built in
   `StartView.swift`: `GroupTitleMenu` (title = Save in), `RecordButtonStyle`,
   `SmallWave`, `PageModelStatus` (download bar + Pause on the page).
   Greeting, WaveMark, GroupChooser and MicStatusLine removed; version
   number is in the gear menu and Settings > Updates. Recording view
   header (E3) not changed yet: ask Ryan after he tries this.
   Test build 0.1.171 (CI screenshots checked: matches the mockup;
   Record centered beside the title; recording page not in screenshots).
   Test list: 1) start screen looks like E, Record is your Mac's accent
   color; 2) click the title, pick English, Record, it saves there;
   3) title menu > New Group… names a new group; 4) "+" on a group opens
   this screen with that group as title, doesn't record; 5) Recently
   deleted > New recording opens this screen; 6) gear menu names and
   Settings > AI Apps; 7) narrow window: Record moves under the title.
   Then (Ryan: "fix that too"): recording page matches the start page.
   Recording before the first words now shows the header and a left
   "Listening. ..." hint where the first line goes (was a centered
   "Listening." that jumped). `TranscriptList.emptyHint`. Every transcript
   header ends with the same 1.5 pt ink rule. Start page uses the
   transcript's geometry (760 column, 32 side, 24 top, 70 gutter) and
   header order (date eyebrow, 30 pt serif title, "Using the X mic.").
   Pause/Stop stay in the bottom bar (they'd scroll away in the header).
   Test 8) press Record: title, line and hint stay put, "Listening."
   shows where the first line goes. When Ryan says good: open the PR
   (milestone), merge to main.

## Merged to main (2026-11-12, late)
`claude/claude-connector` (lag fixes, mini window, design pass, connector,
gear menu, notes, diagnostics) and `claude/mini-window-crash` are in main.
- 0.1.150 crashed opening the mini window while idle: the old
  "VerbatimMiniWindow" autosaved frame (pre-redesign size) plus
  `sizingOptions = [.preferredContentSize]` made AppKit and SwiftUI resize
  the window in a loop (stack overflow in layout). Fix in 0.1.153: the mini
  window sizes itself after layout (`MiniWindow.contentResized`), content is
  `.fixedSize` vertically, only the top-left spot is saved
  (`MiniWindowTopLeft`), the old key is removed. Smoke test seeds the old
  key. Ryan tested 0.1.153: good. BUT the old code with the old key did
  NOT crash on the CI Mac (repro run 47), so the trigger is not proven;
  the loop is gone either way. If it crashes again, get the report.
- Recording freeze FIXED (Ryan, 0.1.153: "smooth now no freeze"). Cause
  and rule in `DECISIONS.md` ("Nothing that moves while recording...").
- Connector works only in the Claude desktop app on Ryan's Mac. Ryan
  mostly uses cloud Claude, where it can't reach his Mac. Idea offered, not
  decided: save transcripts to a repo so cloud Claude can read them.
- `claude/mini-crash-repro` is a throwaway branch: delete on GitHub.
  (2026-11-19: every `claude/*` branch is merged or throwaway; Ryan can
  prune them all. Keep `main` and `ci-smoke`.)
- Cleaning branches: Actions tab > "Delete merged branches" > Run workflow
  (`.github/workflows/prune-branches.yml`). Deletes branches with nothing
  that isn't in main and no open PR; keeps main and ci-smoke. Chats can't
  delete branches themselves (the session can only push its own branch).

## State of Ryan's three asks (2026-11-12, evening)
All on branch `claude/claude-connector` (it holds the lag fix, the mini
window, the design pass, the connector and the gear menu). Not in `main`,
not tested by Ryan. Ryan was asked to delete the other branches on GitHub
(Claude's access can't delete branches).
- **Claude connector: BUILT.** `Sources/Verbatim/Connector/`. `Verbatim
  --mcp` (see `Launch` in VerbatimApp.swift) is a read-only MCP server over
  stdio, written by hand (no library), protocol 2025-06-18: tools
  `list_recordings`, `read_transcript` (recording = id, name words or
  "latest"; last_minutes, from_minute, to_minute, marked_only),
  `search_transcripts`. `Library` reads recording.json, live.json and
  groups.json straight from disk and must never touch RecorderModel or the
  other live objects (it runs as a second copy while the app may be
  recording). Settings > Claude (`ClaudeSettings`, `ClaudeConnector`) adds
  `mcpServers.verbatim` to `~/Library/Application Support/Claude/
  claude_desktop_config.json` (keeps a copy of the old file once). The
  smoke test pipes real requests into `Verbatim --mcp` and checks the
  answers (`mcp.txt` on `ci-smoke`): passed. NOT checked: the real Claude
  app picking it up on Ryan's Mac. Connector test list:
  1. Settings (gear menu or ⌘,) > Claude > Connect to Claude.
  2. Quit Claude (⌘Q), open it. In the chat box: + > Connectors: Verbatim
     is there.
  3. Ask "What's in my latest Verbatim recording?". Claude asks to use
     Verbatim, then answers from the transcript.
  4. Try while recording: "what did he just say" (about 10 s behind).
  When notes are built, add them to `Library.text`.
- **Gear menu: BUILT** (`GearMenu` in SidebarView.swift, no mockup: it's a
  normal Mac menu). Grey icon; menu: Settings, Keyboard Shortcuts, Connect
  to Claude, Check for Updates, Get Help or Send Feedback (GitHub issues),
  Copy Details for Claude, version. `SettingsNav.shared.page` picks the
  Settings page. Not seen open in a screenshot.
- **Notes on lines: BUILT** (Ryan: "build the specified notes"), not tested
  by Ryan. `Model/Notes.swift`: `LineNote` (time, text) in
  recording.json `notes`, matched to lines like markers
  (`Notes.byLine`). `RecorderModel.setNote` (Undo), `requestNote` (⇧⌘N,
  toolbar Note button, ⌘K) sets `noteRequest`, which `TranscriptList`
  picks up and starts typing (`noteEditor`, `NoteRow`). Copies and exports
  add "(Note: ...)" under the line (Markdown: a quote line); the connector
  shows and searches notes; the header counts them. Not in the mini
  window yet. Notes test list:
  1. Right-click a line > Add note, type, Enter: shows under the line with
     a pencil. "Note added. Undo" at the bottom.
  2. While recording press ⇧⌘N (or the Note button): typing starts under
     the line being said. The transcript holds still while you type.
  3. Click a note: change it. Empty it + Enter: deleted. Undo both.
  4. Copy all and paste somewhere: "(Note: ...)" is under its line.
  The mockup it was built to:
  https://claude.ai/artifact/Pnh8vYCydmaZ53roYAyXUt, copy in
  `docs/design/Notes.html`. One note per line, under the line with a
  pencil, warmer color. Add: right-click > Add note, a Note toolbar button,
  ⇧⌘N (the line being said now). Click to edit, empty = delete, Undo.
  In copies: "(Note: ...)" under the line. Header counts notes.

## Next asks from Ryan (2026-11-12), written down by the design pass chat
1. **Notes on lines.** Right-click a line > Add note (and a shortcut),
   for things like "Mr. Yurt wrote x on the board". Shown under the line,
   small, with a nice UI (ux-planner, mockup first). Notes ARE included in
   Copy and Export (Ryan picked this), so Claude sees them. Store like
   markers (per line start, in recording.json), editable and deletable
   with Undo.
2. **Claude connection as a tool call.** Ryan wants Claude to call
   Verbatim itself (not copy and paste): a local MCP server so the Claude
   desktop app can list recordings, read a transcript (with notes and
   markers) and search. Claude first, ChatGPT later (it can use MCP too).
   Everything stays on the Mac. Note DECISIONS.md "no AI chat inside the
   app": this is Verbatim as a tool for Claude, not chat in Verbatim.

3. **Sidebar gear button** (small, do it first in the next chat): it shows
   in the blue app tint (`SettingsLink` with `.borderless` in
   `SidebarView`'s bottom bar). Ryan wants a better color (ink or
   secondary, like the other sidebar icons). And clicking it should pop UP
   a menu like Claude's account menu (his screenshot: Settings ⌘,, Usage,
   Language, Get help, Send feedback, ...), so things are one click away.
   No accounts in Verbatim, so pick what fits, for example: Settings ⌘,,
   Shortcuts, Check for Updates, What's new, Get help / Send feedback
   (opens GitHub issues), Copy Layout Details ⌃⌘L. Mockup first.

## Build order (one milestone per chat)

Order is chosen so Ryan can test real accuracy at home early, before any
class depends on it.

0. [x] **Layout design.** Approved mockup in `docs/design/`.
1. [x] **Skeleton + build.** SwiftUI app, GitHub Actions builds a zipped
       .app into GitHub Releases. Ryan downloads and opens it.
2. [x] **Record.** Record / Pause / Resume / Stop into one crash-safe audio
       file. Sleep prevention, mic picker, level meter, crash recovery.
2b. [x] **Visual design.** "Notebook" look picked by Ryan and built.
       App icon: done 2026-11-20 (the red Ribbon, see "App icon" below),
       on branch `claude/ux-round-2`, not tested by Ryan yet.
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
7b. [x] **Markers** (Ryan said yes, 2026-11-10). Merged, not tested. ⌘D while recording or
       right-click a line > Add marker here (also after class). Flag next to
       the time. Copy and export put "⚑ " in front of marked lines. "Copy
       marked parts only". Undo in the bottom bar.
7c. [x] **Voice memory** (Ryan's ask, 2026-11-10). Merged, not tested. Remember a voice once
       Ryan names it, so next time "Mr. Yurt" is named by itself. Sortformer
       can enroll saved voice audio (`enrollSpeaker`); check FluidAudio's
       docs on how well it maps. Needs a "Voices" list to rename or forget.
8. [x] **Corrections memory.** Word list via Parakeet vocabulary boosting
       (~100 MB extra download, Ryan said yes), fix rules, Words screen.
       Merged 2026-11-11 (RywnSwn/Verbatim#16) before testing, at Ryan's ask
       (see "How the word list works" and its test list).
9. [x] **Storage.** History sidebar, 7-day audio delete, Storage screen,
       Recently deleted, Export everything. Merged 2026-11-11
       (RywnSwn/Verbatim#17) before testing, at Ryan's ask (see "How storage works").
10. [x] **Polish.** Groups with icons, menu bar, mini window, quiet banners, ⌘K,
        auto names, fuller Settings, text size, battery warning, compact layout.
        Merged 2026-11-12 (RywnSwn/Verbatim#18). Ryan saw it on 0.1.93 to 0.1.99;
        still check: sidebar crash in a small window fixed in 0.1.99?
        (see "How step 10 works" and its test list).
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
- App icon: the red Ribbon (2026-11-20), see "App icon" below.

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
- App icon (2026-11-20, picked by Ryan after 6 rounds, all in
  `docs/design/AppIcon.html`, live page
  https://claude.ai/artifact/36WZyRqXNNYMaz3ziksCF5): a cream printed page
  with a red satin bookmark ribbon (Note red), real paper grain, light and
  shadow. Source: `Support/AppIcon.svg`. `node scripts/make-icon.js` makes
  `Support/AppIcon.icns` (works on Linux, uses Playwright).
  `scripts/build-app.sh` copies it; Info.plist has `CFBundleIconFile`.
  Built on `claude/ux-round-2` (Ryan asked), not tested by Ryan yet.
  Test: the new icon shows in the Dock, Finder and Launchpad (if the old
  blank one sticks, drag Verbatim out of Applications and back in).
  What Ryan said no to: waveform turning into lines, anything "generic",
  busy icons with many ideas, the "Quote V" (looked like a suit), blue and
  yellow together, flat single shapes ("too blank"). What worked: ink on
  paper, made like a real object (modern skeuomorphism).
  Not done: a separate dark-mode icon (needs Xcode's new icon format).

## How the design pass works (2026-11-12)
- Sidebar (`Views/SidebarView.swift`) is a ScrollView + VStack, not `List`:
  List always paints its own selection highlight over our boxes. So we do
  click (onTapGesture), arrow keys (`onKeyPress`, `visibleIDs`), Delete
  (`onDeleteCommand`), right-click (row `.contextMenu`, empty space menu on
  the ScrollView) ourselves.
- Rows: `SidebarRow` draws the box from `RowLook` (soft: ink 4.5/8.5/15%,
  cards: `Theme.card` + shadow, open card ink with paper text).
- Drag: `.onDrag` (sets `SidebarDrag.shared.id`, the row shows as an empty
  outline) + `LiftedRow` as the drag picture. macOS never says when a drag
  is cancelled, so `SidebarDrag` watches `NSEvent.pressedMouseButtons` and
  ends when the button is let go. Each group and Recents is one
  `SidebarDropDelegate` zone: proposes `.move` (no green plus), lights up
  (`DropHighlight`, "Move here"), folded group opens after 0.65 s, drop
  moves and offers Undo via `offerLineUndo`. Delegate methods are
  nonisolated + `MainActor.assumeIsolated` (works either way the SDK marks
  DropDelegate).
- Glass/solid: `SidebarLook`, solid = `Theme.sidebarSolid` behind the
  scroll view. Reduce transparency forces solid (the CI Mac has it on, so
  smoke screenshots always show solid; glass only on Ryan's Mac).
- Settings (`Views/SettingsView.swift`): NavigationSplitView with
  `SettingsPage` list, every page a `.formStyle(.grouped)` Form, first
  section header is `PageHeader` (lede + first group name). Two-Text
  labels give the grey explanation under a row. New pages: Look
  (`LookSettings`, tiles `LookTile`), Shortcuts (`ShortcutSettings`).
  Storage has `SpaceBar`.
- Smoke test also opens Settings (General, Look, Transcription) and
  relaunches with solid + cards.
- Known small thing: Transcription shows the word list helper download
  twice (inside the speech model line and its own row). Was like that
  before.

- Lag fix (same day, Ryan: "transcription at the start super laggy",
  timer, waveform and text lag, all catch up on Pause): the speaker model
  (Sortformer) used FluidAudio's default compute units `.all`, so it could
  run on the GPU, which also draws the window. Now `.cpuAndNeuralEngine`
  (`SpeakerEngine.computeUnits`), like Parakeet and the word spotter. Ryan
  (same day): STILL very laggy, so this was not it (or not all of it). He
  wants the next chat to look at it. Ideas to check: (1) the word spotter
  (CTC 110M) runs on every Parakeet chunk while the word list has words,
  try with an empty word list; (2) main thread: `LiveTranscriber.apply`
  (LineBuilder + `fix` over the whole text) and `TranscriptList` body
  (Speakers.labeler, Markers, rows) run on every volatile/final update;
  (3) memory on 8 GB (Parakeet + Sortformer + CTC + Apple Intelligence
  naming): ask Ryan to check Activity Monitor > Memory pressure while
  recording; (4) did it start with step 7 (speakers) or step 8 (word
  list)? Add a timing log (main-thread hitch counter in Copy Layout
  Details) so Ryan can paste real numbers.

- Speaker names (same day, Ryan: one-time names piled up in the speaker
  menu, no way to remove them): `SpeakerNames` (observable, UserDefaults
  `recentSpeakerNames`, last 8). Remove from Settings > Voices ("Names
  offered in the speaker menu", X buttons, Undo) or the speaker menu's
  "Forget a Name" submenu (Undo in the bottom bar). Transcripts keep names.

## Design pass test list for Ryan
1. Recordings each sit on a light box. Pointer over one: darker. The open
   one: darkest, name bolder.
2. Settings (⌘,) > Look: Solid, then Glass. Paper cards, then Soft boxes.
   The sidebar changes right away.
3. Drag a recording onto another group: it lifts, a gap stays, the group
   lights up and says "Move here", no green plus. Drop: "Moved to ... Undo"
   at the bottom. Click Undo.
4. Drag, then press Esc or let go somewhere empty: it goes back.
5. Hold a drag over a folded group for a moment: it opens.
6. Click a recording, then ↑ / ↓ keys move through the list. Right-click
   still has Rename, Move to Group, Delete.
7. Look through every Settings page. Anything cut off or odd?
8. Settings > Voices: remove an old speaker name with its X, then Undo.
   Click a speaker name in a transcript: "Forget a Name" works too.
9. Record 2 to 3 minutes: timer, waveform and text stay smooth?
10. Icon picker: Color on one line, Remove Icon and Done fit.

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

## How markers work (step 7b)
- `Model/Markers.swift`. Saved as times (seconds into the audio) in
  recording.json (`RecordingInfo.markers`), not on lines, so they survive
  Transcribe again and Find speakers. A line is marked if a marker falls
  between its start and the next line's start.
- ⌘D (Recording > Add Marker) and the toolbar "Marker" button while
  recording mark 1.5 s ago (you press just after hearing it). ⌘D also works
  while the player plays a finished recording. Right-click a line: Add
  marker here / Remove marker. "Marker added at 10:41. Undo" in the bottom bar.
- Flag just left of the time in the gutter.
- Copy and export put "⚑ " in front of marked lines. Copy arrow menu and
  Transcript menu: "Copy marked parts only" ("Nothing marked yet" if none).
- Not done yet: menu bar dropdown "Add marker" (comes with the menu bar in step 10).

## Step 7b test list for Ryan
1. Record, press ⌘D while someone talks: a flag shows by that line, "Marker
   added at ..." with Undo at the bottom. Try the toolbar Marker button too.
2. Right-click a line in an old recording > Add marker here, then Remove marker.
3. Play a recording, press ⌘D: the line being heard gets the flag.
4. Copy arrow > Copy marked parts only: just those lines, with ⚑ in front.
5. Export as Markdown: marked lines start with ⚑.

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

## How the word list works (step 8)
- `Model/WordList.swift`: `WordList` (words + fix rules, saved in App
  Support/Verbatim/words.json, starts with Anansi, Nyankupon, Kweku Tsin and
  the fixes Father Nazi -> Anansi, group bonds -> Nyankupon), `Fixes` (the
  text work), `WordModel` (the download).
- Boosting: FluidAudio's `StreamingUnifiedAsrManager.configureVocabularyBoosting`
  with the Parakeet CTC 110M word spotter (~100 MB, ~64 MB extra memory,
  loaded with Parakeet only while the list has words). Set in
  `ParakeetEngine.begin()`, so list changes count from the next recording or
  after Pause. An empty list reloads Parakeet (FluidAudio can't switch it off).
- The spotter's model MUST live in FluidAudio's own folder
  (App Support/FluidAudio/Models/parakeet-ctc-110m-coreml): FluidAudio reads
  its tokenizer only from there. Uninstaller trashes that folder too.
- Download order: Parakeet, speaker model, then the word spotter (only if
  the list has words). Retries every 30 s. Shown on the start screen and in
  Settings > Words.
- How fixes reach the text: the token stream is the raw text; the spotter
  rescores about every 15 s and hands back "replace X with Y"
  (`consumeVocabularyReplacements`). `LiveOutput.fixes` carries them, and
  `Fixes.applySpotted` replaces the newest match in the last 40 lines. So a
  misheard name shows for ~15 s, then fixes itself. Word times follow along.
- Fix rules: applied to the newest 2 lines every time words arrive (live and
  files), whole words, any case, punctuation kept, never on locked lines or
  the line being edited. A rule whose result contains its own left side
  ("Yurt" -> "Mr. Yurt") is not applied twice.
- After editing a line: if 1 to 4 words changed (not a single short word
  like "a", not only capitals), an inline line under it asks "Fix X to Y in
  future transcripts too? Remember / Just this once" (`RecorderModel.fixOffer`).
  Remember: saves the rule, fixes the rest of this transcript, adds the right
  side to the word list if it has a capital letter; one Undo in the bottom bar
  takes all of it back. The question goes away on the next edit or on
  switching recordings.
- Right-click a line > Add a word to word list... (name box, bottom bar confirms).
- Settings > Words: both lists, add field under each (inline reason if a
  word is too short, under 3 letters, or already there), minus button to
  remove, Undo under the lists for 10 s.
- Risks to check with Ryan: the spotter could swap a real word for a name
  that sounds close; the ~15 s delay before a name fixes itself; files
  transcribe slower with it (FluidAudio: ~26x real time, so ~2 to 3 min per hour).

## Step 8 test list for Ryan
1. After updating: start screen shows "Downloading the word list helper",
   then nothing. Settings > Words says "Listening for these words".
2. Read aloud something with Nyankupon, Anansi, Kweku Tsin (or play a class
   video): do the names come out right? Some may fix themselves after ~15 s.
3. Click a line, change one wrong word, press Enter: the line under it asks to
   remember it. Click Remember: the bottom bar says what it did. Click Undo.
4. Right-click a line > Add a word to word list..., add a name.
5. Settings > Words: remove a word, click Undo. Add a fix by hand.
6. Import a Voice Memo: how long does it take now?
7. Does any normal word get wrongly turned into a name?

## How storage works (step 9)
- Recently deleted: Delete (was Move to Trash) moves `Recordings/<id>` to
  `App Support/Verbatim/Deleted/<id>` plus `deleted.json` (date).
  `Model/RecentlyDeleted.swift`. Kept 30 days, then removed for good on the
  next load (launch, or opening the list). Sidebar bottom: "Recently deleted
  (N)" (hidden when empty) opens `RecentlyDeletedView` in the main area: Put
  Back, Delete Now (asks), Empty (asks), first words of each transcript.
  Undo in the bottom bar for 10 s still works.
- Old audio: `Model/AudioCleanup.swift`. Setting `audioKeepDays` (3, 7, 14,
  30, 0 = forever; default 7). Counts from Stop (imports: from when they were
  imported, the folder's date). Deleted for good, not the Mac Trash. Skips:
  text not finished, playing, Keep Audio (right-click, `keepAudio`), anything
  Delete Audio Only would refuse. Runs 30 s after launch, then hourly. Never
  deletes in the 2 days after the update (`audioCleanupSince`), so Ryan sees
  the warning first. Sidebar: "audio deletes in 2 days" when 3 or fewer left.
- Settings > Storage: keep audio picker, space used (recordings, speech
  models, Recently deleted), biggest recordings with Delete Audio, Export
  Everything, Delete All Recordings (asks once, then Undo in the bottom bar;
  the recording in progress stays).
- Export Everything: zip via `ditto` with `Transcripts/*.md` (same format as
  Export), `Data/Recordings/<id>/` json files, words.json, voices.json. No audio.

## Step 9 test list for Ryan
1. Right-click a recording > Delete: bottom bar says Recently deleted, Undo.
2. Delete again, then click "Recently deleted (1)" at the bottom of the
   sidebar: Put Back brings it back with its text.
3. Settings > Storage: sizes show, biggest recordings list, Delete Audio works.
4. Export Everything: open the zip, the transcripts read fine.
5. Delete All Recordings, then Undo in the bottom bar.
6. Right-click a recording: Keep Audio has a tick after clicking it.
7. In 2 days: old recordings' audio goes, the sidebar warned first.

## How step 10 works (polish)
Mockup v3: https://claude.ai/artifact/2ii2Hd8QkNtZ6gtxUYHziJ (Ryan approved).
- Groups (`Model/Groups.swift`, groups.json in App Support): one per class,
  SF Symbol icon + soft color (`Views/IconPicker.swift`, ~200 icons with
  search words). `RecordingInfo.groupID`; nil = Recents (old recordings stay
  there, Ryan's call). Sidebar: Section per group (fold), + starts a
  recording in it, right-click empty space > New Group, right-click a
  recording > Move to Group / Change Icon, drag a row onto a group name.
  Group order: right-click > Move Up / Down (no drag).
- Names: new recordings are "Wed 12 Nov" (`autoTitle = true`). Start screen
  has "Save in" (remembers last group). `Model/AutoName.swift`: after the
  text is final, Apple's on-device Foundation Models picks a 2 to 6 word
  title from up to 1,200 words spread over the class. Only once, never
  touches names Ryan typed. Settings > Transcription turns it off and says
  if Apple Intelligence is off.
- `RecordingHeader`: big serif title (click to rename), times, markers, who spoke.
- Menu bar (`Views/MenuBar.swift`, MenuBarExtra .window): template waveform
  image + timer, dot for unseen messages. Big buttons (copy new, marker,
  pause, stop) then text rows. Always shown while recording; Settings hides
  it otherwise.
- Mini window (`Views/MiniWindow.swift`): floating NSPanel, top left, all
  desktops, remembers position. ⇧⌘M, toolbar button, menu bar.
- Messages (`Model/Messages.swift`): front = bottom bar only; mini open =
  mini window; behind other apps = dot + Dock badge, important ones (still
  recording, battery, mic/disk problems) also a silent banner; window
  closed/minimized = silent banner for everything incl. Voice Memo done and
  3 h stop. No sound ever. First window close while recording: one banner
  "Verbatim keeps going in the menu bar".
- "Still recording?" after 5 min quiet by default (Ryan), Settings 5/10/20/30/never.
- Battery: checked every 60 s while recording, warns once at 15% on battery.
- ⌘K (`Views/CommandMenu.swift`): actions, Record in group, Go to recording.
- Text size ⌘+ / ⌘− / ⌘0 and a Settings slider (`TextSize`), transcript only.
- Timer digits roll (`.contentTransition(.numericText())`), bottom bar
  messages slide in/out. Ideas from Ryan's library list, done natively.
- Compact layout (Ryan, like Claude): window narrower than 860 pt hides the
  sidebar by itself (`ContentView.columns`), back at 940 pt. Window min 680x500. Sidebar changes wait for the layout pass to end (0.1.98 crashed when it did not).
  Start screen scrolls when short. Sidebar min 220, no main area min.
- Not done: "Download again" button for models (they already re-download by
  themselves); drag to reorder groups; Mac-wide notification tests.

## Step 10 test list for Ryan
1. Right-click empty sidebar space > New Group, name it "English 2026", click
   its icon, search "book", pick a color. Make "World Studies 2026" too.
2. Press + on a group: records right away, named after today, inside the group.
3. Drag an old recording onto a group name. Right-click > Move to Group back.
4. Record 2+ min of a lecture video, Stop, wait ~15 s: does it get a real name?
5. Close the window while recording: banner once, menu bar shows waveform +
   timer. Click it: big buttons work, Open Verbatim brings the window back.
6. ⇧⌘M: mini window top left. Switch to another app, it stays on top. Drag it.
7. Hide the window behind others, stay quiet 5 min: silent banner with Stop.
8. ⌘K, type "mark", Return. ⌘+ and ⌘− change transcript size.
9. Settings: General sections, Transcription tab, DJI mic in the list.

## Weekly bug hunts
Ryan asked for this on 2026-11-18. A scheduled task ("Weekly Verbatim bug
hunt") starts a fresh chat every Saturday at 9:38 Myanmar time. It sends 3
reviewer agents over the code changed since the last hunt, checks what they
find, and lists real bugs here (it never fixes code itself). Ryan can turn
it off or change it in the claude.ai scheduled tasks list. It costs a fair
amount of usage each time it finds new code, nothing when there is none.
Last commit hunted: none yet (first hunt covers the whole app).

## Faster start-up: DONE 2026-11-18 (branch `claude/faster-startup`)
Measured with the smoke test: 200 old classes with ~330 KB live.json each
(about 66 MB of text) in a folded group, plus the usual 3.
Seconds after the app started (first launch / second launch):
- Before (4a18d3c): saved classes read 2.24 / 2.01 (2.12 / 1.98 of it
  with the main thread blocked), window shown 3.86 / 2.81.
- After (e1191bd): saved classes read 0.35 / 0.41 (0.27 / 0.36 blocked),
  window shown 1.42 / 2.01. First launch read the 201 texts in the
  background, done at 2.62 s. Second launch had nothing to check.
- What's left on the main thread (~0.3 s) is reading the 203
  recording.json files.
The answers Claude gets (MCP) were the same before and after.
How it works now:
- `Live/TextIndex.swift`: `text-index.json` (next to the Recordings
  folder) keeps `TextFacts` per recording (has lines, file pass finished
  or not, stopped by Ryan, speakers found, has voices, backup engine) plus
  the size and date of the live.json they came from.
- `LiveTranscriber.start(with:)` reads that one file and checks each
  live.json's size and date. Entries that don't match (first launch after
  this update, a quit between saves, Put Back, an older Verbatim) are read
  off the main thread one at a time (`checkInBackground`), then
  `Transcriber.textChecked(id)` picks up unfinished work for that one.
- `texts[id]` reads the live.json the first time something asks for it
  (opening, copying, exporting, finding speakers, MCP). Old Whisper
  transcripts (`Transcriber.transcripts[id]`) the same way.
- `facts(id)`: nil = still being checked. Old audio cleanup skips those.
- The index is saved 2 s after a change and at quit.
- recording.json files are read once at launch, not twice.
- `Model/LaunchTimer.swift`: "LAUNCH: ..." lines in the log and in ⌃⌘L
  (seconds after the app process started).
Faster start-up test list (for Ryan):
1. First launch after the update: the app opens, and within a few seconds
   everything looks as before (old classes, their names, checked text).
2. Open an old class: its text shows right away. Copy it, export it: same.
3. Quit and open again: should open a bit faster. Press ⌃⌘L and paste the
   "LAUNCH" line to Claude.
4. Record a short class, Stop, quit within a few seconds, open again:
   the class and its text are all there.
Not done (found here, for later):
- Every time the app becomes active (`didBecomeActive`), `reload()` reads
  every recording.json again on the main thread. Small now, grows with a
  year of classes. Only reload when something changed.
- While recording, the whole live text is encoded and saved every 10 s on
  the main thread. A long class could make that a small hitch. Save off
  the main thread (fits item 3, protect data).

## Line edit fix, ⌘Z, thinner rule (2026-11-19, branch `claude/fix-line-edit-undo`)
Ryan's report: while editing a line, clicking another line copied the
edited text into that line and replaced it. Also asked for a "hitbox" over
the page while editing (mini window too), an undo feature, and said the
rule under the title was thick with the spacing off.
- Cause of the copy bug: one shared `LineDraft` box for all edits. The old
  TextField writes its text one last time as it closes, after `begin` had
  put the new line's text in the box, so the new line got the old text.
  Fix: `begin` (TranscriptList, MiniLines) and `beginNote` make a new box.
- `TypingShield` (TranscriptList.swift): while a line or note is typed,
  every other line, the header, the gaps and margins are covered; a click
  only saves. Right-click on other lines is covered too (click once first).
  Mini window: other lines just save (`MiniLineRow.covered`).
- Undo: `offerLineUndo` now pushes onto `undoStack` (last 50, until quit).
  Edit > Undo ⌘Z (`RecorderModel.undo`): in a text box it undoes typing,
  else a deleted recording/audio still showing Undo, else the newest change.
  Flashes "Undid: line edited." Redo only works for typing.
- Rule: 1 pt in `Theme.rule` (was 1.5 pt full ink). Start page now has the
  same space as a transcript header: 14 above, 24 to the first line; the
  hint sits above the model status so an empty status adds no gap.
Test list (for Ryan):
1. Click a line, change it, click a different line: the first line saves,
   the second is NOT changed and does not open. Click it again to edit it.
2. Same in the mini window while recording.
3. Edit 3 lines, then press ⌘Z three times: each goes back, newest first.
   While typing in a line, ⌘Z undoes typing only.
4. Start page: the line under the title is thin and the gap above and
   below looks even. Press Record: title, line and text don't jump.
Same day, Ryan: the gap between the sidebar and the title was too big.
The start page and every transcript header (title, details, rule) and
the "Listening" hint now start at the page edge (32 pt from the sidebar),
not 70 pt in past the time gutter. Transcript lines keep the gutter: the
times sit under the title's left edge. Test: start page title is close to
the sidebar; open a class: its title starts at the same spot; press Record:
nothing moves sideways.
Same day, Ryan: copies and exports had no time or speaker, and the time
in the gutter wrapped ("10:42 A" / "M").
- Times in copies (Settings > General) now default ON
  (`TimeStyle.includeInCopies`); it was off by default.
- Speakers: the code already writes `[Mr. Yurt]: "text"`. The smoke test
  now presses Copy All and fails if "Mr. Yurt" is missing (copy-all.txt in
  `ci-smoke`). If it passes there but Ryan still sees none, ask how he
  copies and which recording (a Voice Memo before speakers were found?).
- Gutter: 60 pt + 10 pt gap (was 52 + 18, same 70 total), one line always.
Same day, Ryan: live text takes a few seconds after Record, and after an
early Stop (30 s, no words yet) the page showed a big "Transcribe" screen.
- Cause: every Record loaded Parakeet (+ word spotter) and the speaker
  model from disk first; they're unloaded at Stop to free memory.
- `LiveTranscriber.warmUp()` / `LiveRunner.warm()`: the start page loads
  them while it's open (StartView .onAppear, when the model gets ready, and
  after the Transcriber's queue empties if the start page is showing).
  Runs in the same chain as recordings (`runTask`), so Record mid-load just
  waits. Not while recording or while a file is transcribed. The
  Transcriber calls `coolDown()` before its own Parakeet loads (8 GB: one
  at a time). Known voices are still played to the speaker model at Start.
- No more `emptyState` screen in PastRecordingView: always the transcript
  page, with a hint where the first line goes: "Finishing the text…" while
  the live run is still on that recording, "No text yet. Transcribe" (link)
  when nothing is working on it, else as before.
Test: open the app, wait 10 s on the start page, press Record and talk:
words should come within ~2 s. Stop after 10 s: same page, words fill in.
If still slow, paste ⌃⌘L ("LIVE TEXT START" line).

## Protect data (code health item 3, 2026-11-19)
Merged (RywnSwn/Verbatim#25), tested by Ryan 2026-11-19.
- Stop and Quit (and ⌘Q a moment after Stop, while live text is still
  catching up): the app answers `.terminateLater`, shows "Saving the last
  words, then Verbatim quits…", waits for the live run to finish (max
  20 s, `LiveTranscriber.finishBeforeQuit`), saves, then quits. Logout
  path (`applicationWillTerminate`) calls `saveNow()`.
- live.json saves all go through one serial queue (`LiveTranscriber.disk`).
  The every-10-s save while recording runs there in the background; edits
  wait for it (`sync`), so an old text can't land on a new one. `writes`
  counts saves per recording so a late background save doesn't put old
  facts in the index. A failed save says so once per recording.
- recording.json: every save goes through `RecorderModel.persist`. On
  failure it says "Couldn't save the change to X..." once and keeps the
  change in memory (`unsaved`); `reload()` (on app activation) tries it
  again and keeps the in-memory copy instead of the old file.
- Record while a file is being transcribed: live text waits for the file's
  models to unload (`Transcriber.modelsFreed`) before loading its own, so
  two Parakeets are never loaded at once. Audio is saved meanwhile and
  live text catches up.
Test list (for Ryan):
1. Record, talk for 20 s, then ⌘Q > Stop and Quit right after a sentence.
   Open the app again: the last sentence is in the text.
2. Record, Stop, then ⌘Q within 2 s: same, nothing missing at the end.
3. Import a long Voice Memo, and while it says "Transcribing", press
   Record and talk: live text comes after a short wait (maybe "catching
   up"), the app doesn't freeze or crash. Stop: the file carries on.
4. Rename a class, add a note and a marker, click another app, click back:
   all still there (this always worked when the disk is fine).

## Next asks (Ryan, 2026-11-19), one chat, branch `claude/listen-audio-add-line`
(built on `claude/protect-data`, so merging it brings item 3 too)
1. Better playback audio. Audio was 16 kHz, squashed to 32 kbps AAC after
   Stop: muffled to listen to. Ryan picked 48 kHz: record a 48 kHz copy for
   listening and shrink it gently after Stop (~45 MB per hour is fine, he
   deletes audio after reviewing). Parakeet keeps getting 16 kHz and the
   transcripts must not change.
2. Add line below. Right-click a line > "Add line below": an empty line to
   type in, time between the lines around it, speaker from the line above
   (click the name to change it), locked like an edit, ⌘Z undoes it.
   Follows the typing rule (one box open, click away saves, no copying).
3. Small: `AudioPipeline` drops the right channel of a stereo mic (no
   downmix), so a 2-mic receiver in split mode loses one mic. Fix.
Not doing: echo removal (could damage his voice in the recording).
Built 2026-11-19, tested by Ryan and merged (RywnSwn/Verbatim#26):
- Audio: `AudioPipeline` takes the mic's own format (no audioSettings) and
  makes two mono files from the same sound with its own converters
  (`downmix = true`, best resampler): audio.wav 16 kHz (Parakeet, speaker
  model, live text, level meter: as before) and listen.wav 48 kHz (only
  for the player, `RecordingStore.playbackURL`). If listen.wav can't be
  written, it's dropped and playback uses the 16 kHz audio. Undo Stop
  carries on listen.wav, padded with silence to stay in step; crash
  recovery repairs it too. `bytesPerHour` counts both while recording
  (~460 MB/h before shrinking).
- `AudioSquash`: audio.wav > audio.m4a 32 kbps (unchanged, ~14 MB/h, what
  Transcribe again reads) and listen.wav > listen.m4a 64 kbps 48 kHz
  (~29 MB/h). Total ~43 MB/h. Delete Audio, old-audio cleanup and the
  size in the sidebar menu use `RecordingStore.audioFiles` (all four).
  Imports and older recordings have no listen copy: they play as before.
- Note: the 16 kHz audio is now made by Verbatim's converter, not macOS's
  (it used to keep only the left channel). Same rate and format for
  Parakeet; a mono mic gives the same sound.
- Add line below (`TranscriptList` `adding`, `RecorderModel.addLine`,
  `newLineTimes`, `LiveTranscriber.discardLine`): right-click a live line.
  The new line is a draft in the view until it has text: empty = nothing
  added. Its own `LineDraft` box and focus; focus loss does not save (the
  name menu may take it), but a click anywhere else, Enter, starting any
  other edit, or leaving the page saves. Esc cancels. The line above is
  covered like other lines. Time: halfway into the gap before the next
  line (just after the last line at the end). Speaker: the line above's
  (`speaker` field, no voice, so changing it never offers to rename a
  whole voice). Locked. ⌘Z / Undo removes it (no "deleted here" mark).
Test list (for Ryan):
1. Record a class bit (or just talk) for a minute, Stop, wait ~20 s, then
   play it: it should sound clearer than before (not muffled). The words
   in the transcript are the same kind of quality as before.
2. Right-click the recording > Delete Audio Only: the size it shows is
   about 43 MB per hour of recording. Undo brings the audio back.
3. If you have the 2-mic receiver: split mode, one mic each side, record:
   both voices are in the recording and in the live text.
4. Right-click a line > Add line below: an empty line opens under it with
   a time and the speaker of the line above. Type, click somewhere else:
   it's added with a lock. Click the name first to change who said it.
5. Add line below, type nothing, click away: nothing is added.
6. Add a line, press ⌘Z: it goes away. While typing in it, ⌘Z undoes typing.
7. While the new line is open, click another line: it only saves, the
   other line does NOT open and does NOT change.

## Sidebar and line tools (Ryan, 2026-11-20), branch `claude/sidebar-and-line-tools`
Ryan's asks:
1. Sidebar: opening it made the window wider each time ("bigger and
   bigger"). Wants it to use the room the window has, like Claude.
2. Lines: "how do I add a line in between", markers and notes "only apply
   to the latest line, I can't put them anywhere". Also: one click on a
   line starts editing, which "feels dangerous".
3. "Investigate UX errors, I've been noticing a lot."

Built (part 1, not tested by Ryan yet): `ContentView.toggleSidebar` never
resizes the window. Window 760 pt or wider: the sidebar column opens and
the transcript gets narrower. Narrower (680 to 759): `FloatingSidebar`
slides in over the transcript (dimmed); a click outside, Esc, the sidebar
button or picking a recording slides it away. It auto-hides below 760 and
comes back from 820 (was 860 / 940). 760 because the system sidebar button
did nothing below ~745 and opening the column in a too-narrow window
crashed 0.1.98 / 0.1.102. Smoke test: toggles 3 times at 800 and 700 wide,
checks the width never changes, screenshots the floating sidebar, Esc and
click-outside.
Test list (for Ryan):
1. Make the window medium (sidebar showing), close and open the sidebar a
   few times: the window never gets bigger, the transcript gets narrower.
2. Make the window as small as it goes: the sidebar hides. Click the
   sidebar button: it slides over the transcript. Click the transcript, or
   press Esc: it slides away. Pick a recording in it: it slides away.
3. Make the window big again: the sidebar comes back by itself.

Part 2, line tools: BUILT in the same chat at Ryan's ask ("implement
here"), not tested by Ryan yet. Mockup: https://claude.ai/artifact/BSvJ7utAQxyjqokGa3iQ9d
(copy in `docs/design/LineTools.html`).
- `TranscriptList`: one click picks a line (`picked`, blue margin mark,
  `LineHighlight`), double-click (`NSApp.currentEvent.clickCount`) or Enter
  edits, arrows move, Delete deletes, Esc lets go. The list is focusable for
  the keys. Hover: soft grey (own hover state per row, `LineHighlight`).
- Picked line: flag, note, + buttons (`LineActionButton`, 24 pt). + only on
  live lines; since step 5c every new recording's lines are live, also
  after Stop (only old Whisper text is "checked").
- `RecorderModel.lineTool` (`LineTool` in Markers.swift): toolbar Marker and
  Note are now toggles (`LineToolToggle`), in the recording AND finished
  recording toolbars. Pointer: `PointerStyle.image` of a round SF Symbol
  badge (flag yellow, pencil red). Rows get a yellow / red margin mark.
  `LineToolBand` at the top says what a click does, "Put it down" = Esc.
  Marker stays on; Note goes down after one note. Picking a tool saves and
  closes anything being typed. Switching recordings puts the tool down.
- ⌘D / ⇧⌘N / menus / mini window unchanged: they mark or note "now".
- The row text no longer shows a text cursor (a click doesn't type).
Look (Ryan tested: "works excellent", but the tinted box with an outline
"looks AI"): he picked B, Margin mark, from https://claude.ai/artifact/66un6nSsuBUANx9UoRYd7P
(`docs/design/LineLook.html`). No fill or outline on lines; a short pen
line (Capsule, 3 pt) 24 pt left of the line: grey on hover, accent when
picked (time turns accent too), `Theme.markPen` / `notePen` with a tool.
The tool band is plain paper with a pen-colored chip.
Smoke test (0.1.214): margin mark and arrow keys look right; widths never
change. The test's "click" on the dimmed part next to the floating sidebar
still doesn't close it (Esc does), because the test clicks through
accessibility. Ryan tried a real click: it closes. Everything in this
section tested by Ryan and merged 2026-11-20 (RywnSwn/Verbatim#28).
Not done: the mini window still edits a line on one click (Ryan didn't
ask; consider the same pick / double-click rule there).
Test list (for Ryan):
1. Move the mouse over lines: a short grey line shows in the margin. Click
   one: the margin line turns blue and so does the time, nothing opens,
   three small buttons on the right.
2. Double-click a line: you're typing in it. Or click once and press Enter.
3. With a line picked: ↑ ↓ move, Delete deletes it (Undo brings it back),
   Esc lets go.
4. Click + on a picked line: an empty line opens under it. Type, Enter.
5. Click Marker in the top bar: pointer is a yellow flag, lines get a
   yellow margin line,
   a band at the top says so. Click a few lines: flags appear. Click a
   flagged line: flag goes. Esc (or Marker again): tool goes down.
6. Click Note: pointer is a red pencil, lines get a red margin line. Click a line: the
   note box opens there and the tool goes down.
7. While recording, ⌘D still marks what's being said right now.
8. Open an old recording: Marker and Note are in its top bar too.

UX check (2026-11-20, read from the code, worst first). FIXED in this
branch: 1. ⌘Z after deleting a recording (not recording) skipped the delete
and undid an older line change (`undo()` only looked at `status`; delete only
sets `deletedNote`). Now ⌘Z brings the recording back.
Still to do (one chat, after the line tools):
2. Transcribe again / Find speakers again: one click, no warning, no undo;
   voice names and speaker picks on unedited lines are lost
   (`Transcriber.redo` doesn't copy `voiceNames`).
3. Bottom bar: Stop/Delete notes hide every other message for 10 s (Undo of
   a line edit, "Copied", errors). Mini window has the opposite order.
4. No undo for: picking a speaker, renaming a recording, Move to Group by
   menu, group rename/icon. ⌘Z then undoes something older.
5. Lock button unlocks with one click, no message, no undo.
6. Menu bar Stop: no "Saved" and no Undo Stop.
7. Settings deletes (Biggest recordings > Delete Audio, Delete All): the
   Undo is in the main window's bottom bar, hidden behind Settings.
8. Note missing from the mini window and menu bar; menu bar Marker off
   while paused, other Marker buttons and ⌘D work while paused.
9. Small click targets: group +, group icon, Undo links (under 24 pt).
10. ⇧⌘C copies the recording on screen; ⌘K and menu bar "Copy all ⇧⌘C"
    copy the live one while recording.
11. ⇧⌘Z does nothing outside a text box, no message.
12. Same action, different names (Add a Voice Memo / Transcribe a
    Recording / Transcribe a Voice Memo; Copy Layout Details / Copy
    Details for a Bug Report).
13. Shortcuts page says "work anywhere" but ⌘D/⇧⌘N need recording or the
    player; ⌥⌘P, ⌘Z, ⌘G, ⌘0 missing.
14. Emptying a line deletes it, but the line box doesn't say so.
15. Greyed Transcribe again / Find speakers again don't say why.

### UX check, round 2 (2026-11-20, read from the code by 4 reviewers + CI screenshots)
Ryan: "investigate for UX errors". The worst ones (A1 to A5) were checked
by hand in the code. Item 1 above was only half fixed: see A4.

**BRANCH: `claude/ux-round-2`. Keep working on THIS branch (Ryan asked,
2026-11-20): start the next chat by checking it out, not a new branch.**
A1 to A10, B1 to B17, C1 to C11 and items 2 to 15: BUILT on that branch, not tested by Ryan, not merged. Draft pull
request RywnSwn/Verbatim#29 (one PR for the whole round; merge only when
Ryan asks, after testing). Next chat: A6 to A10, then B, then C, all on the
same branch. Smoke 0.1 run 89 (8e6d67b): passed; Copy all shows at 1000 and
at 700 wide (only Note and the rest go into "»" at 700).
Review fixes (second reviewer, same chat): the Undo link only shows for a
change in the recording on screen (a box saved while switching goes on ⌘Z
only); "Copied N lines" never replaces a message with a link; a delete
step is skipped once that recording was put back or deleted for good
(`UndoStep.restores`), and Put Back removes it.
What was built (A1 to A5):
- A1: `AudioCleanup.changed(from:to:)` (called from the Storage picker's
  onChange): shorter than before, or Forever to a number, sets
  `audioCleanupGraceUntil` = now + 3 days; `deleteDate` never goes before
  it, so the sidebar's "audio deletes in N days" shows first and changing
  back loses nothing. Under the picker: "N recordings lose their audio in
  the next 3 days. The text stays." (`AudioCleanup.dueSoon`).
- A2: `TranscriptList.boxOwner`: the recording the open box belongs to,
  used by save / saveNote / saveNewLine. `onChange(of: info.id)` saves and
  closes the box, clears the picked line and popups.
  `keepNewLineAnchored` only runs in the box's own recording.
- A3: `WavWriter.recoverAfterError` (truncate to the last good sample),
  `AudioPipeline.hasWriteError` / `clearWriteError`. `resume()` refuses
  with "The disk is still full. Free up space, then Resume" under about
  10 min of room, else fixes the file and records again.
- A4: `undoStack` holds `UndoStep` (text, recording, run). `offerLineUndo(
  _, in: id)` everywhere a change is in one recording. ⌘Z
  (`undoLastChange`) takes the newest step whose recording is on screen
  or being recorded, or has none; steps of a deleted recording wait until
  Put Back. Other recording's step: "Undid: … (in <title>)". Nothing:
  "Nothing to undo in this recording." Recording delete is a step
  (Put Back); the bar's Undo removes it. ⌘Z after Stop = Undo Stop if no
  newer step (`StoppedNote.serial` vs `undoSerial`). Opening another
  recording clears the "Line edited. Undo" link (`selectionChanged`).
- A5: Copy all is the first toolbar item (finished and live recording),
  since a narrow toolbar hides items from the right into "»". The bare
  toolbar "+" (New recording) is gone (sidebar top and ⌘N still there;
  also fixes part of C1). Copy shows "Copied N lines" in the bottom bar
  when not recording.
Test list (for Ryan, A1 to A5):
1. Open a finished recording, normal window size: Copy all shows next to
   the title buttons, not hidden in "»". Press ⇧⌘C: "Copied N lines" at
   the bottom.
2. Double-click a line, type something, click another recording in the
   sidebar. Go back: your words are in the first recording; the other
   recording didn't change.
3. Same with a note (pencil button) and a new line (+ on a picked line).
4. Edit a line in recording A, open recording B, press ⌘Z: "Nothing to
   undo in this recording." Go back to A, ⌘Z: the edit is undone.
5. Delete a recording, wait 20 seconds, press ⌘Z: it comes back.
6. Record a few seconds, Stop, press ⌘Z right away: recording continues.
7. Settings > Storage: change "Keep audio for" to 3 days. The line under
   it says how many recordings lose audio in the next 3 days. Change it
   back to 7 days. (Nothing is deleted for 3 days either way.)
8. Disk full can't be tested easily; skip it.

A6 to A10: BUILT (2026-11-20, second chat on the branch), not tested by
Ryan. `claude/speech-model-errors` was checked first: it does NOT fix A10
(its `recordingFinal` still needs `isModelReady`); it only clashes with this
branch in the notes files, so it stays its own PR (RywnSwn/Verbatim#27).
Its `recordingFinal` line will conflict with A10: keep both (`needsRedo`
from #27, the new `!isModelReady` enqueue branch from here).
What was built (A6 to A10):
- A6: `AudioImport.convert` reports progress (by the file's length) and
  stops on task cancel. `RecorderModel.runImport` keeps the task in
  `importTasks`; `cancelImport(id)` = Cancel link in the status line
  ("Importing X, 42%. Text comes next.", with a bar). `delete(id)` and
  Delete All on an importing recording cancel the copy (folder removed,
  "Stopped importing X. Your original file isn't touched."), so nothing
  half done goes to Recently deleted. `RecordingInfo.importingPath` is set
  until the copy is done: at launch (`recoverImports`) the copy starts over
  if the file is still readable, else it's removed and a notice says
  drop it in again. `Transcriber.pickUp` skips importing ids. Same file
  dropped twice while copying: shows the first.
- A7: queued + model download paused: "Needs the speech model. Its
  download is paused at 42%." with "Resume download"; failed: "Try now";
  downloading: "Starts when the speech model download is done (42%, about
  3 min left)."
- A8: menu bar panel with mic access off: "Verbatim can't hear anything",
  Record becomes "Mic settings", Record in <group> rows greyed. `start()`
  with mic off sets a status with "Open Microphone settings"
  (`Status.Action.openMicSettings`) instead of doing nothing. The panel
  re-reads the permission when it opens.
- A9: `pause()` ends keep-awake (the Mac may sleep; nothing is recorded)
  and `askIfStillPaused` asks once after 15 min: bottom bar "Paused for
  15 minutes. Class over?" with Stop, and a "Still paused?" banner (same
  id as Still recording, with Stop / Keep going). Off when "Still
  recording?" is off in Settings. A pause for a problem keeps its own
  message and Resume link. Resume takes keep-awake again.
- A10: `recordingFinal`: no text, no pass, Parakeet not ready, audio there
  = `enqueue`; it waits in the queue (status line says the download) and
  `modelReady()` starts it. Picked up again after a relaunch as before.
Test list (for Ryan, A6 to A10):
1. Drop a long Voice Memo (10 min or more) on the window. Under the
   title: "Importing …, N%" with a bar, then "Transcribing …".
2. Drop it again and press Cancel while it says Importing: it goes away,
   "Stopped importing …" at the bottom. Drop it again, press Delete
   (⌘⌫) while Importing: same thing, nothing in Recently deleted.
3. Drop a long memo and quit Verbatim (⌘Q) while it says Importing. Open
   Verbatim: it imports again from the start, then transcribes all of it.
4. Mic access: System Settings > Privacy & Security > Microphone, turn
   Verbatim off. Click the menu bar icon: it says Verbatim can't hear
   anything, with a Mic settings button. Press ⌘R in the main window:
   the bottom bar says so with "Open Microphone settings". Turn it back on.
5. Record, Pause, wait 15 minutes (or come back later): "Paused for 15
   minutes. Class over?" with Stop. The Mac can go to sleep while paused.
6. A7 and A10 need a fresh Mac without the speech model, so they can only
   be checked on a test account. Skip them.

B1 to B17, C1 to C11 and the older list's items 2 to 15: BUILT (same
chat, 2026-11-20), not tested by Ryan, same branch and PR. Two code
reviews done (A6 to A10, then all of B); their findings are fixed.
Smoke passed for b7432ac (B8 to B17). How the trickier parts work:
- B1: `Status.standing` marks a warning that stays true (battery, chosen
  mic missing, quiet, disk almost full, paused for a problem, 10 min
  before 3 h). `status` didSet keeps it in `warning` while a short message
  covers it and puts it back after. `clearStanding` ends one for good.
  `show()` makes way after 30 s while recording if a warning waits.
  Automatic update check failures only reach the bar after 3 days of
  failing (`updateFailingSince`), never while recording.
- B2: `RecordingInfo.breaks` (pause/resume and asleep/woke events, pauses
  under 30 s skipped) draw "Paused 10:12 to 10:20" dividers (`Row.pause`).
- B11: `liveModelPausedAt`, `speakerModelPausedAt`, `wordModelPausedAt`
  remember Pause. Speaker and word downloads never run at once.
- B13 / item 2: `settingsUndo` and `addUndo` put steps on ⌘Z without the
  bottom bar link; `transcribeAgain` / `findSpeakersAgain` keep the old
  LiveText and put it back on Undo (after the pass has stopped).
- B14: `startNewGroup` / `cancelNewGroup` / `finishGroupName`.
- B16: imports go to `groupOnScreen`; sidebar groups take `.fileURL` drops.
Last two leftovers: BUILT (2026-11-20, third chat on the branch), not
tested by Ryan:
- B10 rest: `ZipDownload` (URLSession delegate) gives progress, shown in
  Settings > Updates as "Downloading 0.1.N: 42% (17 of 40 MB)". If it
  stops (internet, sleep), URLSession's resume data is kept in
  `Updates/<build>.partial` and the next try carries on from there
  ("The download stopped at 42%. It carries on from there in 30
  minutes, or press Check Now."). Resume data that no longer works:
  starts over once by itself. Check Now is greyed while downloading.
- Undo of Transcribe again on an old recording puts its Whisper
  transcript (transcript.json) back too (`Transcriber.putBackOld`).
  Also works when the recording had no live text.
Sidebar fix (5c97fd3, same branch): if opening the sidebar would grow the
window, the window goes back and the overlay is used; the width it needed
is remembered (`sidebarNeedsWidth2`). Smoke run 98 passed.
Fix (same chat): Ryan made the window small (overlay), dragged it wider,
and after that the sidebar button only gave the overlay. Dragging wider
reopened the sidebar mid-drag, and the rest of the drag (the last width
change lands just after the drag ends) looked like the sidebar growing the
window, so a wrong width was learned. Now: no growth watch while or after
a drag, growth over 320 pt isn't the sidebar, and the old key is dropped
once (new key `sidebarNeedsWidth2`).
Test list (for Ryan, these two):
1. Settings > Updates, Check Now when a new test build is out: the line
   under it counts up ("Downloading …: 42% (17 of 40 MB)").
2. Same, but turn Wi-Fi off halfway: it says the download stopped at N%.
   Wi-Fi on, Check Now: it carries on from about N%, not from 0.
3. Old recordings from before Parakeet are rare; skip the Whisper Undo.
4. Open the sidebar at different window widths: the window never grows.
5. Make the window small (sidebar becomes the overlay), drag it big again:
   the normal sidebar comes back, and the sidebar button gives the normal
   one (not the overlay) from then on.
Lesson (2026-11-20): a review subagent ran `git checkout <sha>` in the
shared checkout, so commits made meanwhile landed on a detached HEAD and
weren't pushed. Tell review agents to use `git show` / `git diff` only,
never checkout, and check `git status -sb` before pushing.
Test list (for Ryan, B, C and the older items; the main ones):
1. Record, put the Mac to sleep a minute, wake it: "Mac was asleep" and a
   divider line in the transcript. Pause over 30 s, Resume: "Paused …"
   divider.
2. While recording, unplug the charger under 15% (or wait for "Quiet for
   5 minutes"), then press ⌘D: the marker message shows, then the warning
   comes back by itself.
3. Delete a line that has a flag and a note: both go, Undo brings all
   three back.
4. Settings > Words: remove two words, press ⌘Z twice: both come back.
5. Right-click a recording > Move to Group > New Group…, then Cancel: no
   new group, the recording is where it was.
6. Drop a Voice Memo on a group name in the sidebar: it lands in that
   group. Drop one while recording: you stay on the live page.
7. ⌘F a speaker name and a word from a note: both are found and marked.
8. More (⋯) > Transcribe again, then Undo in the bottom bar: the old text
   and names come back.
9. Rename a recording, change a group's icon, move a recording with the
   menu: each has Undo.
10. Start page while recording: "A class is being recorded right now.
    Show it". Drag a file over the window: dashed outline.
11. ⌘Q while recording, Stop and Quit: the bar says Saving, no Undo Stop.
12. Settings > Updates: if an update is ready, "Restart to Update" is there.

A. Loses work or blocks the task
- A1. Settings > Storage: lowering "Keep audio for" (7 to 3 days) deletes
  older audio for good within the hour (`AudioCleanup.sweep`, removeItem).
  No count, no warning days, no undo. Fix: say "N recordings lose their
  audio" under the picker and give the normal days of warning.
- A2. Typing in a line / note / new line, then clicking another recording:
  the text is lost, or saved into the OTHER recording at the same time.
  `PastRecordingView` / `TranscriptList` have no `.id(info.id)`, so the
  open box carries over; `EditKey` has no recording id. Fix: `.id(info.id)`
  and keep the recording id in each open box.
- A3. Disk full mid-class, free space, Resume: looks like recording, saves
  nothing for the rest of class. `AudioPipeline.failed` is only reset in
  `attach`, Resume only calls `startCapture`. Timer and bars freeze.
- A4. ⌘Z is one list for all recordings: undoes a change in a recording
  not on screen ("Undid: line edited."), or does nothing for one in
  Recently deleted but still says "Undid". ⌘Z after Stop undoes an old
  edit instead of Undo Stop (`undo()` ignores `stoppedNote`). ⌘Z after
  deleting a recording only works for 10 s (`deletedNote`), later it
  undoes something older. Fix: tag undos with their recording, put Undo
  Stop and recording deletes on the ⌘Z list.
- A5. Normal window (about 1000 wide, sidebar open), finished recording:
  Copy all is pushed into the "»" overflow (smoke 08, 09). ⇧⌘C then shows
  no message at all ("Copied" only shows on the hidden button).
- A6. Voice Memo import: no progress, no Cancel. Delete it while importing
  then Undo: "Importing…" forever at 0 min, Transcribe again greyed until
  relaunch (`setImporting(false)` skipped). Quit mid-import: half the memo
  is transcribed and marked done (imports start as `.stopped`).
- A7. Download paused, then a memo dropped: "Waiting for the speech model
  download to finish (42%)" forever, no Resume link there.
- A8. Mic access off, Record in the menu bar panel: panel closes, nothing
  happens. The panel has no blocked state (mini and main window do).
- A9. Paused and forgot: Mac never sleeps (keep-awake kept), no "Still
  paused?" ever (quiet check only runs while recording). Fix: let it
  sleep, ask after about 15 paused minutes.
- A10. First class before Parakeet with no Apple engine: page says "text
  comes after you press Stop" but nothing is queued until relaunch
  (`recordingFinal` needs `isModelReady`).

B. Frustrating
- B1. One status spot: offline, the auto update check's "Update didn't
  work" takes it over for the whole class (every 4 h). Standing warnings
  (battery 15%, chosen mic missing, quiet, disk almost full, paused-on-error
  reason) vanish after any short message (⌘D, edit) and never come back.
  Fix: auto-check failures only in Settings > Updates; warnings get their
  own slot.
- B2. Lid closed over 5 min: "Mac was asleep" is replaced at once by
  "Still recording?" (`didWake` doesn't reset `lastLoud`). The spec's
  "Paused 10:12 to 10:20" / "Mac was asleep" dividers are not drawn
  (events are saved, no view reads them). Tip shows every wake, not once.
- B3. Record fails to start: a 0 min ghost recording stays (folder made
  before the failing step), next launch says "Verbatim quit during…". The
  error has no hint what to do.
- B4. Deleting a line moves its flag and note onto the line above (notes
  get joined). Fix: they go with the line, in the same Undo.
- B5. Audio playing: the list follows the audio and scrolls the note or new
  line being typed off screen (only `editing` stops it). Also pulls back a
  line picked with arrows.
- B6. Double-click with the Note tool: opens the line's text instead of
  the note. With Marker: adds then removes the flag ("Marker removed.").
- B7. ⌘F doesn't find notes or speaker names that are on the page.
- B8. Keyboard: after Enter/Esc closes a box, arrows do nothing until a
  click (`listFocused` only set by mouse). Nothing picked: arrows ignored.
  Line picked, then click the same recording in the sidebar, Delete:
  deletes the whole recording; no pane shows which has the keyboard.
- B9. Switches ON that can't work: "Name recordings from what was said"
  next to "This Mac can't run Apple Intelligence" (smoke 21); banners on
  while macOS notifications are denied; voice "Use" on but not used (only
  3 newest count). Fix: grey out with the reason and an Open Settings
  button.
- B10. Updates: once a build is downloaded, no newer one is ever found
  until restart. No Restart button in Settings > Updates (only the lowest
  priority bottom bar). Update download has no progress, no resume, next
  try in 4 h.
- B11. Downloads: the speech model says "about 600 MB", then speaker
  labels and word helper (100 MB each) start one after another with no
  Pause and no "1 of 3". Pause is forgotten at next launch. Speaker retries
  and the word download can run at the same time.
- B12. Live text off: mini window and menu bar still say "Words show up
  here a couple of seconds after…". Reason is always "still downloading"
  even when paused, failed or Apple's engine is missing. Speech
  Recognition permission is first asked when pressing Record in class, and
  when denied there's no Open Settings button.
- B13. Settings Words / Voices: only the last removal has Undo, not on ⌘Z.
  Return in "Heard as" does nothing. Errors look like grey hints.
- B14. New Group…, then Cancel: the group is still made (and from Move to
  Group, the recording is already in it).
- B15. Delete the group the start screen records into, Undo: start screen
  now says Recents, next ⌘R records there.
- B16. Memo dropped on the start screen showing "English": lands in
  Recents. Memos can't be dropped on a sidebar group. Dropping one while
  recording leaves the live page.
- B17. Sidebar never scrolls to or unfolds the recording that just opened
  (import of an old memo, Put Back into a folded group, + on a folded
  group).

C. Polish
- C1. Icons: toolbar "+" = New recording, but "+" on a picked line = add a
  line, sidebar "+" = record into group. Pencil on a line = note. "»" and
  "⋯" unlabeled. Flag tooltip still says "Right-click to remove".
- C2. Header counts raw markers: ⌘D twice in one line = 1 flag, "2 markers".
- C3. Import messages: "Transcribed the first 0 min" when nothing ran; raw
  "OSStatus error -11829"; picker offers .flac then refuses it; only the
  first bad file named; no highlight when dragging a file over the window.
- C4. Start screen reachable while recording (greyed Record, "The class
  shows up on this page"). Mic denied hides the memo hint and downloads.
- C5. Floating sidebar stays open when clicking the recording already open.
- C6. Change Icon on a recording: picking a color before an icon is ignored.
- C7. Settings > Transcription shows speaker and word downloads twice;
  "Tells Mr. Yurt apart from students" (Ryan turned down class-only words).
- C8. AI Apps says "Verbatim was moved" when a second copy (test build) is
  open but the first is still there.
- C9. Remove Verbatim and Its Data: quitting writes `text-index.json` and
  makes the data folder again.
- C10. ⌘Q, Stop and Quit: bar shows "Undo Stop" instead of "Saving…";
  Undo Stop there still quits. Undo Stop at the 3 h limit stops again at
  once (no warning before 3 h). Undo Stop doesn't close the player.
- C11. Faint text on the start screen ("The class shows up…", "Or drop a
  Voice Memo here") is hard to read.

Can't tell from code, test on Ryan's Mac: dragging straight out of the
Voice Memos app (file promise vs file URL); first "Still recording?"
banner lost while macOS asks for notification permission mid-class;
right-click on the sidebar hint text itself; mic unplugged mid-class when
the runtime error comes before the disconnect note (may stay paused).
