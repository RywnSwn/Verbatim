# Weekly bug hunts

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). "UX check item 2" is in `sidebar-and-line-tools.md`; "the 48 kHz notes" are in `listen-audio-add-line.md`.

## Weekly bug hunts
Ryan asked for this on 2026-11-18. A scheduled task ("Weekly Verbatim bug
hunt") starts a fresh chat every Saturday at 9:38 Myanmar time. It sends 3
reviewer agents over the code changed since the last hunt, checks what they
find, and lists real bugs here (it never fixes code itself). Ryan can turn
it off or change it in the claude.ai scheduled tasks list. It costs a fair
amount of usage each time it finds new code, nothing when there is none.
Last commit hunted: cd185a5 (2026-11-21).

### Hunt 1 (2026-11-21, commit cd185a5, the whole app)
16 bugs, checked against the code by hand (nothing run, no Mac here).
Worst first. Fix a few per chat.
FIXED on branch `claude/hunt-1-fixes` (2026-11-21, not tested by Ryan
yet): 1, 2, 3, 5, 14, 15. Still to fix: 4, 6 to 13, 16.
1. FIXED. **Data loss.** While recording, pick a speaker on the newest
   line (or unlock it), let the teacher keep talking, then ⌘Z: the words
   said since the pick were deleted (Undo put back a copy of the whole
   line). Now Undo only puts back the pick (`LiveTranscriber.changeLine`)
   or the lock. `Speakers.swift` `setSpeaker`, `LineEdits.swift` `unlockLine`.
   NOTE for `claude/speaker-menu` (not merged, also changes `setSpeaker`):
   keep this field-only Undo when merging.
2. FIXED. **Data loss.** Stop, then delete the recording within a few
   seconds: the last words not saved yet were thrown away. Now
   `saveBeforeMove` saves before the folder moves, and if the live run is
   still going through the last audio (`runs`, not just `activeID`), the
   text stays in memory (`movedAway`) and keeps saving into the Recently
   deleted folder until the run ends. Put Back during the run writes the
   newest text back and it keeps growing there. Quit waits for every run.
3. FIXED. **Missing text.** After a crash, force quit, or Stop and Quit
   while live text was behind, the end of the class stayed missing. Now
   `LiveText.liveUnfinished` is set at Record and cleared when the live
   run is done with the last audio (not by an older run after Undo Stop).
   Still set at launch: `Transcriber.finishLive` runs Parakeet from the
   last line's end (deleted lines count) to the end of the audio, only
   that part. Mac-engine text is redone whole instead, once Parakeet is
   here (the Mac text stays until then). Only recordings made from this
   build on carry the flag. Known gap: the filled-in end gets its own
   speaker numbers (like any resumed file pass); Find speakers again fixes it.
4. **Mixed-up text.** If the Mac's own speech engine was used for part of a
   class (Parakeet still downloading), then Stop and Quit, the 3-hour
   limit, or a normal Stop while live text is over 10 s behind starts the
   Parakeet re-do while the live run is still adding its last words. Those
   words land at the top of the new text and the re-done words from 0:00
   get glued onto them. `Transcriber.recordingFinal` > `redo`, with
   `LiveTranscriber.apply` still running.
5. FIXED. **Wrong name.** Rename a recording's big title, then click
   another recording: the name could go to the other one. Now the header
   remembers which recording the box is for (`renamingID`), and switching
   saves to that one and closes the box. `RecordingHeader.swift`.
6. **Slow, memory (8 GB).** With a file waiting to be transcribed (for
   example a Voice Memo imported during class), Stop while live text is
   behind: 10 s later the file's Parakeet and speaker model load while the
   live ones are still loaded. Two Parakeets at once, the Mac swaps.
   `LiveTranscriber.coolDown` returns at once when `activeID` is still set
   instead of waiting. Also hit by Stop and Quit and the 3-hour limit.
   (Hint: `LiveTranscriber.runs` from fix 2 says which runs are still going.)
7. **Glitch.** Move a recording to Recently deleted while its file is
   being transcribed: a scary "Couldn't save the text" message shows, and
   a bit of its text is made again in memory. `Transcriber.transcribe`
   calls `live.addPass` after the delete, and `addPass` makes a new text
   when there is none.
8. **Slow.** Transcribing a long file: every 30 s piece saves the whole
   transcript to disk on the main thread (about twice a second), so the
   window stutters more and more late in a 2 hour file.
   `LiveTranscriber.addPass` > `commit` > `write` (not `background`).
9. **Slow.** Search in a long transcript: typing lags. Every visible line
   with a hit re-searches the whole transcript up to 3 times.
   `Views/TranscriptList.swift` `highlighted` > `currentMatch` >
   `model.searchMatches`.
10. **Slow.** While audio plays, the whole player bar (buttons, speed menu)
    redraws about 8 times a second because it reads `player.time` itself.
    Breaks the tiny view rule. `Views/PlayerBar.swift`.
11. **Slow.** While recording, every new live line rebuilds the app's whole
    menu bar menus and copies the whole transcript: the Transcript menu's
    `.disabled(!model.hasShownLines)` in `VerbatimApp.swift`.
12. **Slow.** While the Mac's own speech engine is in use (before Parakeet
    downloads), the whole recording page redraws on every half-heard word,
    worse as the class gets longer. `Views/RecordingViews.swift`
    `RecordingNowView` reads `live.volatile`.
13. **Memory.** Open the app (start page loads the live models), then read
    old transcripts for an hour: about 700 MB of models stays loaded until
    the next recording or file. Nothing cools down when the start page
    goes away. `Views/StartView.swift` `.onAppear { live.warmUp() }`.
14. FIXED. **Glitch.** Delete All Recordings, then Empty Recently Deleted,
    then ⌘Z: "Undid" but nothing came back. Undo steps now hold a list of
    recordings they put back (`UndoStep.restores: [UUID]`), Delete All too.
15. FIXED. **Glitch.** Right-click a group > Change Icon… had no Undo. Both
    ways in now go through `GroupHeader.openPicker`.
16. **Slow (rare).** Recording with no internet, Parakeet not downloaded
    and the Mac's own engine not installed: a new download task starts
    every 15 s of audio, about 240 an hour. `LiveRunner.pick`
    `.needsDownload`.
Already in this file, so not listed again: Transcribe again losing voice
names (UX check item 2), the listen.wav drop on a failed write (by
design, see the 48 kHz notes).

Test list for Ryan (hunt 1 fixes):
1. Record, click the speaker name on the newest line and pick someone,
   keep talking 20 s, press ⌘Z: the name goes back and every word you
   said after the pick is still there.
2. Same with a locked line: edit the newest line, right-click > Unlock,
   keep talking, ⌘Z: it locks again, no words lost.
3. Record 1 min, Stop, and right away delete the recording. Press Undo:
   the whole text is there, to the last word (compare with the audio).
4. Record 1 min, then force quit Verbatim (Option-right-click the Dock
   icon > Force Quit). Open it again: the "quit during" note shows, and
   after a moment the last words of the recording appear by themselves.
5. Click a recording's big title, type a new name, then click another
   recording in the sidebar (don't press Enter): the first recording got
   the new name, the other one kept its own.
6. Settings > Storage > Delete All Recordings, then Empty Recently Deleted,
   then ⌘Z: it says "Nothing to undo", not "Undid".
7. Right-click a group > Change Icon…, pick another icon, close: the
   bottom bar offers Undo and it puts the old icon back.
