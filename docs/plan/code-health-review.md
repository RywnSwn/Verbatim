# Code health review (2026-11-18) and the quick fixes (item 2)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). Item 3: `code-health-3-protect-data.md`. Item 4: `code-health-4-speech-model-errors.md`. Item 7: `faster-startup.md`.

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
4. Errors: DONE 2026-11-19 on branch `claude/speech-model-errors`, not
   tested by Ryan yet (see "Speech model errors" at the end). Was: a
   speech model error is swallowed, the app keeps saying "listening".
   Turn the HitchMeter off once the lag is solved (done: freeze fixed).
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
