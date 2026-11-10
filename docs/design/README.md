# Layout reference (approved by Ryan, 2026-11-09)

This is the **layout** Verbatim is built to match. It covers where things go
and how they behave, not the final look (colors, fonts and spacing come in the
visual design step). Don't move things around without asking Ryan.

Live mockup: https://claude.ai/artifact/EyDJd3LDZtiTdGJmcA5vgr (private to Ryan).
The `.dc.html` files here are a copy of it, one per screen.

Since step 5c (Whisper dropped, 2026-11-10) the mockups are out of date in
one way: there is no accurate pass any more. Ignore "Checked up to", grey
live text, "Checking 10:40 to 10:45", "Checking is behind" and the
"accurate model" download in them. Everything else still holds.

## Signature: the waveform
Grey bars when someone talks, grey dots when it's quiet. No color.
- Start screen: it animates into a line of words (audio becoming text).
- Recording: moving bars. This is the "it's recording" signal; there is no red dot.
- Paused: all dots, timer goes grey, the word "Paused" shows.
- Menu bar icon: a tiny version next to the timer.

## Screens
1. **Recording** (`Main.dc.html`)
   - Toolbar: sidebar toggle, title ("English, Mon 10 Nov" / "Mr. Yurt, started 10:05"),
     Marker (⌘D), Search, Export, blue **Copy all** split button. The arrow menu:
     Copy all (⇧⌘C), Copy new since last copy (⌥⌘C), Copy last 10 minutes,
     Copy marked parts only. After copying, the button says "Copied 58 lines" briefly.
   - Sidebar: recordings, newest first ("Today", "This week"). Meta text like
     "Wed 5 Nov, audio deletes in 3 days". Hint at bottom: drop a Voice Memo.
   - Transcript: time in a left gutter (normal font, tabular numbers), a flag icon
     there for markers, **Speaker:** then the text, all in full ink (no "Checked up to" line
     since step 5c: the live text is the transcript).
   - Bottom bar: timer, waveform, Pause (⇧⌘P) and Stop (⌘R) in the middle,
     status spot on the right ("Saved as you go, works offline").
   - Undo toast for markers (and for Stop).
2. **Old transcript** (`Transcript.dc.html`): search box with "2 of 7" and yellow
   match highlights, Export, Copy. Double-click a line to edit (Enter saves, Esc
   cancels). After a word fix: plain text line "Fix X to Y in future transcripts too?"
   with Remember / Just this once links. Edited lines show a lock. Right-click menu:
   Copy this line, Copy from here down, Edit line, Speaker, Add a word to word list,
   Add marker here, Unlock. "Paused 10:20 to 10:38" divider. Sidebar has
   "Recently deleted".
3. **First launch / empty** (`Empty.dc.html`): one screen, no tour. Serif headline
   "Hear it once." / italic "Keep every word.", waveform-to-words animation,
   Start recording (⌘R), "Or drop a Voice Memo here". Below a thin line: mic status
   and the one speech model download (size, time left, resumes, "you can record now").
4. **Menu bar dropdown** (`Mini.dc.html`, replaces the mini window): icon = tiny
   waveform + timer. Dropdown: status line, last 2 lines, Copy new / last 10 min /
   all, Add marker, Pause, Stop recording, Open Verbatim.
5. **Settings** (`Settings.dc.html`): tabs General, Transcription, Words, Storage,
   Updates. Classic Mac form: right-aligned labels, controls on the right, thin
   lines between groups. General: teacher name, "Students show as", microphone
   (MacBook mic default, never auto-switches to AirPods), timestamps (clock / since
   start), include timestamps when copying, shortcuts list.
6. **Messages, undo, importing** (`States.dc.html`, `InContext.dc.html`): all news
   goes in the bottom bar status spot, one at a time, with a text link only when
   action is needed. Nothing pops up and recording never stops. After Stop: thin
   progress line + "Undo Stop". Mic off: takes over the main area with a button to
   the right System Settings page. Voice Memo import and crash recovery: a plain
   line at the top of the transcript with text links.

## Final look (step 2b)
"Notebook": see `Sources/Verbatim/Views/Theme.swift` and PLAN.md "How the look works".

## Style rules learned from Ryan's feedback
- No soft boxes with light borders and rounded corners around everything (reads as
  AI). Use spacing and thin divider lines.
- No red recording dot, no big red record button.
- No colored level meters; mono waveform only.
- No "A · B · C" dot separators; no code font for times.
- Serif (Apple's New York) italic only for big moments; transcript may use a
  normal serif; buttons, menus and settings use the system font. Decide in the
  visual design step.
- Ryan likes an editorial feel (inspiration: Wispr Flow's site), but don't copy
  another app's signature look.
