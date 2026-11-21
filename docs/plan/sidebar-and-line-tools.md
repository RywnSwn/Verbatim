# Sidebar and line tools (RywnSwn/Verbatim#28), plus UX check round 1

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). UX check round 2 (which built items 2 to 15 below): `ux-round-2.md`.

## Sidebar buttons (added at the end of chat 2026-11-09, Ryan's asks)
- Top: "+ New recording ⌘N", like New chat in Claude. Opens the start
  screen; recording begins from its Start recording button (⌘R still
  starts/stops directly). Ryan's ask in step 2b: it used to start at once.
  While recording it reads "Recording now" and jumps to it.
- Bottom: "Transcribe a file…" (same as Cmd+O / drag and drop).
- Updater says "Updated to version X" once after an update.

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
