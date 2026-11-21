# UX round 2 (2026-11-20, RywnSwn/Verbatim#29)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). "Item 1 above" and "the older list's items 2 to 15" are the round 1 list in `sidebar-and-line-tools.md`. Faster builds note: `step-01-build-and-ci.md`.

### UX check, round 2 (2026-11-20, read from the code by 4 reviewers + CI screenshots)
Ryan: "investigate for UX errors". The worst ones (A1 to A5) were checked
by hand in the code. Item 1 above was only half fixed: see A4.

**MERGED into main 2026-11-20 (Ryan: "perfect merge"), RywnSwn/Verbatim#29.
He tried the sidebar changes on 0.1.236; the test lists below were mostly
not run, so if something here breaks, these notes say how it works.**
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
6. The sidebar in the window has no scroll line, and slides in and out
   when you press the sidebar button (it used to just appear and vanish).
7. Scroll the sidebar: New recording, Transcribe and Recently deleted stay
   at the top with a line under them, the settings row stays at the bottom
   with a line over it, and recordings never slide under the window's dots
   or under the settings row.

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
