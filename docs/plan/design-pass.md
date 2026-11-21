# Design pass (2026-11-12): sidebar rows, drag, glass or solid, Settings pages

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

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
