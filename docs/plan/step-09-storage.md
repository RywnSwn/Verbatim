# Step 9: storage

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

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
