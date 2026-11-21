# Mini window redesign (2026-11-12)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

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

## Mini window crash (from "Merged to main (2026-11-12, late)")

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
