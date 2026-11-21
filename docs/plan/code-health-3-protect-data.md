# Protect data (code health item 3, RywnSwn/Verbatim#25)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

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
