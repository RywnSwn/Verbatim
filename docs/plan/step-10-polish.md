# Step 10: polish (groups, menu bar, mini window, messages, ⌘K)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was). Mini window redesign: `mini-window.md`.

## Ryan's feedback: the app feels empty (2026-11-10)
Ryan: "Claude is a simple app but it feels well fleshed out, small things
add up." Settings feels tiny, no "delete all" button. Wants that polish.
Plan: a dedicated chat that does steps 9 (Storage: Recently deleted,
delete all, storage screen) and 10 (Polish: fuller Settings, first-launch
screen, menu bar, small touches) with the ux-planner skill. Start by
listing small touches and showing Ryan a mockup before building.

## How step 10 works (polish)
Mockup v3: https://claude.ai/artifact/2ii2Hd8QkNtZ6gtxUYHziJ (Ryan approved).
- Groups (`Model/Groups.swift`, groups.json in App Support): one per class,
  SF Symbol icon + soft color (`Views/IconPicker.swift`, ~200 icons with
  search words). `RecordingInfo.groupID`; nil = Recents (old recordings stay
  there, Ryan's call). Sidebar: Section per group (fold), + starts a
  recording in it, right-click empty space > New Group, right-click a
  recording > Move to Group / Change Icon, drag a row onto a group name.
  Group order: right-click > Move Up / Down (no drag).
- Names: new recordings are "Wed 12 Nov" (`autoTitle = true`). Start screen
  has "Save in" (remembers last group). `Model/AutoName.swift`: after the
  text is final, Apple's on-device Foundation Models picks a 2 to 6 word
  title from up to 1,200 words spread over the class. Only once, never
  touches names Ryan typed. Settings > Transcription turns it off and says
  if Apple Intelligence is off.
- `RecordingHeader`: big serif title (click to rename), times, markers, who spoke.
- Menu bar (`Views/MenuBar.swift`, MenuBarExtra .window): template waveform
  image + timer, dot for unseen messages. Big buttons (copy new, marker,
  pause, stop) then text rows. Always shown while recording; Settings hides
  it otherwise.
- Mini window (`Views/MiniWindow.swift`): floating NSPanel, top left, all
  desktops, remembers position. ⇧⌘M, toolbar button, menu bar.
- Messages (`Model/Messages.swift`): front = bottom bar only; mini open =
  mini window; behind other apps = dot + Dock badge, important ones (still
  recording, battery, mic/disk problems) also a silent banner; window
  closed/minimized = silent banner for everything incl. Voice Memo done and
  3 h stop. No sound ever. First window close while recording: one banner
  "Verbatim keeps going in the menu bar".
- "Still recording?" after 5 min quiet by default (Ryan), Settings 5/10/20/30/never.
- Battery: checked every 60 s while recording, warns once at 15% on battery.
- ⌘K (`Views/CommandMenu.swift`): actions, Record in group, Go to recording.
- Text size ⌘+ / ⌘− / ⌘0 and a Settings slider (`TextSize`), transcript only.
- Timer digits roll (`.contentTransition(.numericText())`), bottom bar
  messages slide in/out. Ideas from Ryan's library list, done natively.
- Compact layout (Ryan, like Claude): window narrower than 860 pt hides the
  sidebar by itself (`ContentView.columns`), back at 940 pt. Window min 680x500. Sidebar changes wait for the layout pass to end (0.1.98 crashed when it did not).
  Start screen scrolls when short. Sidebar min 220, no main area min.
- Not done: "Download again" button for models (they already re-download by
  themselves); drag to reorder groups; Mac-wide notification tests.

## Step 10 test list for Ryan
1. Right-click empty sidebar space > New Group, name it "English 2026", click
   its icon, search "book", pick a color. Make "World Studies 2026" too.
2. Press + on a group: records right away, named after today, inside the group.
3. Drag an old recording onto a group name. Right-click > Move to Group back.
4. Record 2+ min of a lecture video, Stop, wait ~15 s: does it get a real name?
5. Close the window while recording: banner once, menu bar shows waveform +
   timer. Click it: big buttons work, Open Verbatim brings the window back.
6. ⇧⌘M: mini window top left. Switch to another app, it stays on top. Drag it.
7. Hide the window behind others, stay quiet 5 min: silent banner with Stop.
8. ⌘K, type "mark", Return. ⌘+ and ⌘− change transcript size.
9. Settings: General sections, Transcription tab, DJI mic in the list.

## Fixes after step 10 (2026-11-12)

Fix on 2026-11-12 (branch `claude/fix-stutter-sidebar-sizing`, which has
`claude/step-10-polish` merged into it, RywnSwn/Verbatim#19): Ryan reported
"so many glitches" in the step 10 test builds (sizing, stuttering, the
sidebar) and asked about moving to Tauri. Found and fixed in code: the menu
bar and the whole sidebar were redrawn 20 times a second while recording
(they read `model.elapsed`), and the whole transcript was redone 8 times a
second while audio played (it read `Playback.time`, and every visible line
searched all lines). Rule from now on: a view that reads `elapsed`,
`levels` or `Playback.time` must be a tiny view of its own. Also
`DetailView` now sits in a `GeometryReader`, so a main-area screen that
wants more height than the window can't stretch the split view and push
the sidebar's top and bottom outside the window (Ryan saw that). Keep it.
Mistake to avoid: this chat first branched from `main` when step 10 was
still on its own branch, and Ryan got a test build with the old design.
Check `git branch -r` for unmerged work before starting. Not tested by Ryan yet. Ask him for
a glitch list (what he did, what he saw). Tauri: see `DECISIONS.md`, not
decided by Ryan yet.
Same day: 0.1.102 crashed for Ryan when he clicked the sidebar button
(AppKit "too many Update Constraints passes" from the split view, same
family as the 0.1.98 crash). Could NOT be reproduced on the CI Mac, but
the test showed the system sidebar button did nothing below about 745 pt
wide (no room). Fix in 0.1.109: our own sidebar button
(`ContentView.toggleSidebar`, ⌃⌘S, system one removed); a window narrower
than 860 pt is widened first, then the sidebar opens. Sidebar footer got a
solid background (rows showed through the text). Not confirmed by Ryan yet;
he was asked whether the window was narrow (sidebar hidden) or wide when it
crashed. If it still crashes, get the new crash report and that answer.

Same day, the real cause of "sidebar top and bottom outside the window"
(found with Ryan's Help > Copy Layout Details output, 0.1.115):
NavigationSplitView made itself as tall as its columns WANTED (title bar +
start screen content + bottom bar = 692 pt) instead of the window (552 pt).
Fix in 0.1.117: both columns get `.frame(minHeight: 0, idealHeight: 300,
maxHeight: .infinity)` in `ContentView` (keep these). The smoke test now
fails if the split view's height differs from the window's. Help > Copy
Layout Details (⌃⌘L, `Views/LayoutDetails.swift`) stays: ask Ryan for it
whenever something is in the wrong place. His menu bar hides Help behind
the notch, so tell him the shortcut. Ryan confirmed it ("finally") and asked to merge: step 10 and these fixes
are on `main` since 2026-11-12 (RywnSwn/Verbatim#19 into #18 into main).
