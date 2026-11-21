# Start screen E, AI Apps, gear menu names (2026-11-18, RywnSwn/Verbatim#21)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Next asks from Ryan (2026-11-18): MERGED to main (RywnSwn/Verbatim#21)
`claude/general-names-simpler-start` and `claude/fix-live-text-delay` are in
main, merged at Ryan's ask before his test. Test list below still to do.
Done (not tested by Ryan yet):
1. Gear menu: "Copy Details for a Bug Report" (other choices offered to
   Ryan: "Copy Problem Details", "Copy App Details"). "Connect to Claude"
   in the gear menu is now "Connect to AI Apps".
2. Settings page "Claude" is now "AI Apps". Claude row stays first; new
   "Other AI apps" row with Copy Setup (the `mcpServers` JSON with this
   app's path and `--mcp`, `ClaudeConnector.setupText()`). Wording no
   longer says only Claude. Enum case stays `.claude`.
3. New recording never starts by itself: the "+" on a group and its
   "New Recording Here" call `model.showNewRecording(in:pickGroup:)`,
   which opens the start screen with that group in "Save in". ⌘K "Record
   in" and the menu bar "Record in" still start right away (asked for
   by name there). Found why New recording "didn't work": from Recently
   deleted it set `selection = nil`, but `showingDeleted` stayed true, so
   the screen didn't change. Fixed.
4. Start screen: mockup https://claude.ai/artifact/Bx3y11h4r3KMAz1s9EnCbh
   (A: one white box with "Save in" + Start, like Claude's chat box, mic
   name in one small line, status only while something downloads; A
   first-time state; B: one big round button; and today's for comparison).
   Ryan: A is "too much like chat". Looked at similar apps: Voice Memos
   (no start screen, one red record button always in the same spot),
   Granola and Otter (home is your list of recent notes, record is a
   small button), Apple Notes (record from a toolbar button). Added C
   (a "Today" page: Record top right, last 3 classes in the group below)
   and D (record button docked at the bottom like Voice Memos). Waiting
   for Ryan to pick. Ryan then picked **E, "a blank notebook page"**:
   the group name is the page title (click it to pick another group),
   date and mic under it, Record button on the right of the title line,
   an empty ruled page below ("The class shows up on this page as it's
   said."), footer with last class link and "Or drop a Voice Memo here".
   When recording, the same page fills in (no jump). No greeting, no
   centered box. Button: Verbatim wave icon, no red dot, no black pill.
   Color not final: Ryan likes warm red #B5523F, also looked at
   notebook blue #2F5F9E and plum #6A5A8E. States drawn: E1 ready,
   E2 first time (download + "Make a group" link), E3 recording,
   E4 group menu open. Next: Ryan picks the color, then build it in
   `StartView.swift` (and the recording view's header to match E3).
   Ryan then: "right direction but looks weird", links look weird, what
   about dark mode. Cause: the mockup's sidebar didn't match the real app
   (CI screenshots: dark mode, floating glass sidebar, group icons,
   recording cards). Redrew E in the real look, dark and light, with no
   underlined links (last-class link dropped, Pause is a small button).
   Mockup row "E, in the real app's look". Ryan: no lines on the page
   (removed), Record button in the **Mac's system accent color**
   (`NSColor.controlAccentColor`, not Theme.accent). Built in
   `StartView.swift`: `GroupTitleMenu` (title = Save in), `RecordButtonStyle`,
   `SmallWave`, `PageModelStatus` (download bar + Pause on the page).
   Greeting, WaveMark, GroupChooser and MicStatusLine removed; version
   number is in the gear menu and Settings > Updates. Recording view
   header (E3) not changed yet: ask Ryan after he tries this.
   Test build 0.1.171 (CI screenshots checked: matches the mockup;
   Record centered beside the title; recording page not in screenshots).
   Test list: 1) start screen looks like E, Record is your Mac's accent
   color; 2) click the title, pick English, Record, it saves there;
   3) title menu > New Group… names a new group; 4) "+" on a group opens
   this screen with that group as title, doesn't record; 5) Recently
   deleted > New recording opens this screen; 6) gear menu names and
   Settings > AI Apps; 7) narrow window: Record moves under the title.
   Then (Ryan: "fix that too"): recording page matches the start page.
   Recording before the first words now shows the header and a left
   "Listening. ..." hint where the first line goes (was a centered
   "Listening." that jumped). `TranscriptList.emptyHint`. Every transcript
   header ends with the same 1.5 pt ink rule. Start page uses the
   transcript's geometry (760 column, 32 side, 24 top, 70 gutter) and
   header order (date eyebrow, 30 pt serif title, "Using the X mic.").
   Pause/Stop stay in the bottom bar (they'd scroll away in the header).
   Test 8) press Record: title, line and hint stay put, "Listening."
   shows where the first line goes. When Ryan says good: open the PR
   (milestone), merge to main.
