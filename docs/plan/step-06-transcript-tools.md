# Step 6: transcript tools (copy, export, search)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

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
