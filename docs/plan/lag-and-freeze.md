# Lag while recording and the recording freeze (2026-11-12)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). One more lag note sits in `design-pass.md` ("Lag fix (same day...)"). The rule that came out of it is in `DECISIONS.md`.

Lag while recording (2026-11-12, branch `claude/fix-recording-lag`, not
tested by Ryan yet, not merged): Ryan said recording lags and that it
defeats the point (fixing lines live). Found in code, could not be measured
(no Mac here):
1. `RecordingHeader` read `model.elapsed`, so 20 times a second the header
   counted every word of the transcript ("X and Y spoke"). Slower the longer
   the class ran. Now the ticking line is its own view, `HeaderMeta`.
2. Typing in a line being edited changed `@State draft` of `TranscriptList`,
   so every key press redrew the whole transcript. Now `LineEditor` keeps
   its own text and writes it to a plain box (`LineDraft`) that the list
   reads when saving.
3. Each row of the transcript's `ForEach` now makes exactly one view (a
   `VStack`). With a different number per row, the lazy stack builds every
   row on each change. Keep it one view per row.
4. `MiniView` read `elapsed` and `levels`; that part is now `MiniClock`.
Not touched: `MenuBarLabel` still redraws 20 times a second (it draws the
moving bars in the menu bar). If Ryan still sees lag, ask WHICH lag: words
showing up late after they're said (Parakeet is about 2 s behind by design),
the app stuttering, or typing being slow, and whether it gets worse the
longer the recording runs. Then look at `MenuBarLabel` and at
`LiveTranscriber.apply` (it changes `texts`, which every transcript view
reads) and the pretty-printed live.json save every 10 s on the main thread.

Merged together (2026-11-12, Ryan's ask): `claude/mini-window-redesign` now
holds the lag fix + the mini window + `claude/design-pass` (another chat's
work: sidebar rows, drag, glass or solid, Settings pages, speaker model off
the GPU, forget speaker names). Test builds from this branch have all of
it. Only `scripts/ci-smoke.sh` clashed (both parts kept). Not merged into
`main` yet: Ryan tests first.
Lag came back (Ryan, 2026-11-12 evening, after the design pass was merged
in): the one live-audio difference between the builds that felt fine
(0.1.135, 137: lag fix only) and the ones that lagged (139+) is
`SpeakerEngine.computeUnits = .cpuAndNeuralEngine` from the design pass
chat. Put back to `.all` (FluidAudio's default). Not confirmed by Ryan yet.
⌃⌘L now also says "LIVE TEXT BEHIND THE MIC: X s now, worst Y s"
(`LiveFeed.behind`): audio waiting for the models. If that grows while
recording, the models are too slow (not the drawing). If lag is still
there, get that paste before changing anything else.
What the lag really is (Ryan, 2026-11-12, on 0.1.141): "it's just stopped
basically; I pause it, the words appear and the timer updates". His ⌃⌘L
paste: while recording 47 checks all fast, then one check that took 151 s
and only came back after Pause (it was counted under "not recording", fixed
now). So a few seconds into a recording the MAIN THREAD stops running its
queue (timer, bars and text all arrive through it) until capture stops.
Not the header, not typing. Cause still unknown. From 0.1.146 the meter
runs `/usr/bin/sample` on Verbatim when the main thread has been stuck
1.5 s during a recording and ⌃⌘L pastes the main thread's stack ("STALL
SAMPLE") plus the longest gap between audio buffers ("MIC"). NEXT STEP:
get that paste from Ryan and read the stack. Do not guess again.
Second and third pastes (0.1.146): mic fine (no gaps), live text 14 s
behind then 0 after Stop, main thread answering only every 1 to 5 s while
recording, CPU idle in the sample (threads waiting, not computing). Ryan:
all text flies in on Pause or Stop, the rest of the app is fine, memory is
not it. Reading: the main thread is jammed while audio is captured, and
LiveRunner needs about 7 main-thread hops before the first word, so text
waits too. Suspect (NOT confirmed): `MenuBarLabel` was fed `levels` and
`elapsed` 20 times a second; a menu bar item is drawn outside the app, so
each change is a round trip to macOS. 0.1.148 feeds it `menuBars` and
`menuClock` (2 changes a second at most). 0.1.148 also prints the main
thread's stack from the saved sample (`Diagnostics/stall.txt`), even after
a relaunch: get that paste to confirm or kill this suspect.
CAUSE FOUND (stall sample from 0.1.146, pasted on 0.1.148; the menu bar
change did not help): 70% of the main thread's time was in
`CA::Transaction::commit > -[RBLayer display] >
RB::SharedSurfaceGroup::add_subsurface > wait_for_allocations >
-[CAContext waitForCommitId:timeout:] > mach_msg`. So SwiftUI's renderer
(RenderBox, macOS 26) blocks the main thread inside a commit, waiting for
the screen to show earlier drawing before it hands out another drawing
surface. Ryan also saw it run smoothly for a moment whenever something
else redrew the window (⌃⌘L's message bar). What made so many surfaces:
`Waveform` was 40 shapes switching between Circle and Capsule 20 times a
second, the timers had `.contentTransition(.numericText())` with an
animation every second, the sidebar's live row had a repeating
`.symbolEffect`. 0.1.149: Waveform is one Canvas, no rolling digits, no
repeating symbol effect. NOT confirmed by Ryan yet. If it still freezes:
get a new sample (⌃⌘L after a freeze) and look at what is under
`-[RBLayer display]`; next things to try: `.drawingGroup()` on the bottom
bar, fewer text updates (timer once a second), the transcript's scroll
animation.
Lag numbers: `Model/HitchMeter.swift` checks ten times a second how long
the main thread takes to answer. ⌃⌘L (Copy Layout Details) now ends with
"MAIN THREAD ... while recording: N checks, N slower than 0.1 s, worst
X s". If Ryan still sees lag: have him record a few minutes, press ⌃⌘L and
paste. Many slow checks = the app's own drawing is the problem (look at
views). Few or none while it still feels laggy = it's the models or
memory (word spotter, 8 GB), not the drawing.

## From "Merged to main (2026-11-12, late)"

- Recording freeze FIXED (Ryan, 0.1.153: "smooth now no freeze"). Cause
  and rule in `DECISIONS.md` ("Nothing that moves while recording...").
