# Speaker menu, top bar line, sidebar learned width (RywnSwn/Verbatim#31)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Speaker menu (Ryan, 2026-11-20), branch `claude/speaker-menu`
Ryan: renaming Speaker 1 didn't change all Speaker 1s; "everywhere"
seemed to rename the wrong people; picking a person should change all of
that speaker's lines. Causes: `Labeler` numbered only unnamed voices by
word count (renaming renumbered the rest), the main picker changed one
line, and voice renames skip lines set one by one. Built:
- `Speakers.numbers` + `LiveText.voiceNumbers`: first heard = Speaker 1,
  given once and kept (`LiveTranscriber.keepNumbers` in `put`/`commit`,
  and in `setVoiceName` before the name is set). `applyVoices` (Find
  speakers) clears them, since its voice numbers are new.
- `Labeler.root` follows "#v5" chains; `count` = lines showing that name.
- Menu (`TranscriptList.speakerItems`): "Rename X (N lines)…", section
  "X is really (all N lines):" (other speakers + past names: picking one
  renames the whole voice, a speaker joins them), "Just This Line"
  submenu (`lineOnlyItems`: picker + Someone Else…), Forget a Name. Lines
  with a typed one-line name or no voice get the one-line choices only.
- `renameVoice` acts on the root voice; a typed name equal to another
  speaker's name joins them (no two Mr. Yurts); same name = nothing.
  `setSpeaker` is one line only, with Undo (no "Change them too").
- Rename alert: OK greyed out while empty; message says how many lines.
Test list for Ryan:
1. Open a recording with Speaker 1 and 2. Rename Speaker 1 to Mr. Yurt:
   every Speaker 1 line changes, and Speaker 2 is still Speaker 2.
2. Click a Speaker 2 name: the menu says how many lines. Under "Speaker 2
   is really", pick a name: all Speaker 2 lines change. Undo puts them back.
3. Rename Speaker 3 to the same name as another speaker (like Mr. Yurt):
   they become one; renaming Mr. Yurt again changes both.
4. Just This Line > pick someone: only that line changes. ⌘Z undoes it.
5. Rename box: OK can't be pressed while the name is empty.
6. While recording: the numbers don't swap as the class goes on.
Update (same day, Ryan: "still very confusing"): the menu is now one
question. Section "Who is Speaker 2? (14 lines)": every other speaker and
past name (picking one changes all those lines), then "New Name…" (alert
"Who is Speaker 2?", OK greyed while empty). Then Divider, "Just This
Line" submenu, Forget a Name. No separate Rename item.
Top bar (Ryan): its own section like the sidebar's top rows:
`.scrollEdgeEffectStyle(.hard, for: .top)` on the detail column plus an
always-there `Divider()` in its top safe-area inset (the hard edge alone
only showed once text scrolled under). Build v0.1.245.
Extra tests: click a name: "Who is Speaker 2? (N lines)" heads the menu;
pick a person: all N lines change. The top bar has a thin line under it
on every page, and text scrolls under a solid bar.
Sidebar slides away too early (Ryan, same day): on the CI Mac it stays
beside the transcript down to 760 pt on every page (smoke 780 shot: top
bar tucks items into »), so Ryan's Mac had learned a big "needs width"
(could be up to 1100). Now `sidebarNeedsWidth3` (old keys dropped once),
learning capped at 860 (`ContentView.maxLearned`), and Copy Layout Details
has a "SIDEBAR:" line (from N pt wide, learned or none).
Test: make the window narrower: the sidebar stays beside the transcript
until about 760 pt, then slides away; the sidebar button then opens it
over the transcript. Paste the SIDEBAR line if it hides earlier.
