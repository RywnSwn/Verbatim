# Step 7b: markers

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## How markers work (step 7b)
- `Model/Markers.swift`. Saved as times (seconds into the audio) in
  recording.json (`RecordingInfo.markers`), not on lines, so they survive
  Transcribe again and Find speakers. A line is marked if a marker falls
  between its start and the next line's start.
- ⌘D (Recording > Add Marker) and the toolbar "Marker" button while
  recording mark 1.5 s ago (you press just after hearing it). ⌘D also works
  while the player plays a finished recording. Right-click a line: Add
  marker here / Remove marker. "Marker added at 10:41. Undo" in the bottom bar.
- Flag just left of the time in the gutter.
- Copy and export put "⚑ " in front of marked lines. Copy arrow menu and
  Transcript menu: "Copy marked parts only" ("Nothing marked yet" if none).
- Not done yet: menu bar dropdown "Add marker" (comes with the menu bar in step 10).

## Step 7b test list for Ryan
1. Record, press ⌘D while someone talks: a flag shows by that line, "Marker
   added at ..." with Undo at the bottom. Try the toolbar Marker button too.
2. Right-click a line in an old recording > Add marker here, then Remove marker.
3. Play a recording, press ⌘D: the line being heard gets the flag.
4. Copy arrow > Copy marked parts only: just those lines, with ⚑ in front.
5. Export as Markdown: marked lines start with ⚑.
