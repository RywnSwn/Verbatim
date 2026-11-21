# Claude connector (AI Apps), gear menu and notes on lines (2026-11-12)

Moved from `PLAN.md` on 2026-11-21 (text kept as it was).

## Merged to main (2026-11-12, late)
`claude/claude-connector` (lag fixes, mini window, design pass, connector,
gear menu, notes, diagnostics) and `claude/mini-window-crash` are in main.

- Connector works only in the Claude desktop app on Ryan's Mac. Ryan
  mostly uses cloud Claude, where it can't reach his Mac. Idea offered, not
  decided: save transcripts to a repo so cloud Claude can read them.

## State of Ryan's three asks (2026-11-12, evening)
All on branch `claude/claude-connector` (it holds the lag fix, the mini
window, the design pass, the connector and the gear menu). Not in `main`,
not tested by Ryan. Ryan was asked to delete the other branches on GitHub
(Claude's access can't delete branches).
- **Claude connector: BUILT.** `Sources/Verbatim/Connector/`. `Verbatim
  --mcp` (see `Launch` in VerbatimApp.swift) is a read-only MCP server over
  stdio, written by hand (no library), protocol 2025-06-18: tools
  `list_recordings`, `read_transcript` (recording = id, name words or
  "latest"; last_minutes, from_minute, to_minute, marked_only),
  `search_transcripts`. `Library` reads recording.json, live.json and
  groups.json straight from disk and must never touch RecorderModel or the
  other live objects (it runs as a second copy while the app may be
  recording). Settings > Claude (`ClaudeSettings`, `ClaudeConnector`) adds
  `mcpServers.verbatim` to `~/Library/Application Support/Claude/
  claude_desktop_config.json` (keeps a copy of the old file once). The
  smoke test pipes real requests into `Verbatim --mcp` and checks the
  answers (`mcp.txt` on `ci-smoke`): passed. NOT checked: the real Claude
  app picking it up on Ryan's Mac. Connector test list:
  1. Settings (gear menu or ⌘,) > Claude > Connect to Claude.
  2. Quit Claude (⌘Q), open it. In the chat box: + > Connectors: Verbatim
     is there.
  3. Ask "What's in my latest Verbatim recording?". Claude asks to use
     Verbatim, then answers from the transcript.
  4. Try while recording: "what did he just say" (about 10 s behind).
  When notes are built, add them to `Library.text`.
- **Gear menu: BUILT** (`GearMenu` in SidebarView.swift, no mockup: it's a
  normal Mac menu). Grey icon; menu: Settings, Keyboard Shortcuts, Connect
  to Claude, Check for Updates, Get Help or Send Feedback (GitHub issues),
  Copy Details for Claude, version. `SettingsNav.shared.page` picks the
  Settings page. Not seen open in a screenshot.
- **Notes on lines: BUILT** (Ryan: "build the specified notes"), not tested
  by Ryan. `Model/Notes.swift`: `LineNote` (time, text) in
  recording.json `notes`, matched to lines like markers
  (`Notes.byLine`). `RecorderModel.setNote` (Undo), `requestNote` (⇧⌘N,
  toolbar Note button, ⌘K) sets `noteRequest`, which `TranscriptList`
  picks up and starts typing (`noteEditor`, `NoteRow`). Copies and exports
  add "(Note: ...)" under the line (Markdown: a quote line); the connector
  shows and searches notes; the header counts them. Not in the mini
  window yet. Notes test list:
  1. Right-click a line > Add note, type, Enter: shows under the line with
     a pencil. "Note added. Undo" at the bottom.
  2. While recording press ⇧⌘N (or the Note button): typing starts under
     the line being said. The transcript holds still while you type.
  3. Click a note: change it. Empty it + Enter: deleted. Undo both.
  4. Copy all and paste somewhere: "(Note: ...)" is under its line.
  The mockup it was built to:
  https://claude.ai/artifact/Pnh8vYCydmaZ53roYAyXUt, copy in
  `docs/design/Notes.html`. One note per line, under the line with a
  pencil, warmer color. Add: right-click > Add note, a Note toolbar button,
  ⇧⌘N (the line being said now). Click to edit, empty = delete, Undo.
  In copies: "(Note: ...)" under the line. Header counts notes.

## Next asks from Ryan (2026-11-12), written down by the design pass chat
1. **Notes on lines.** Right-click a line > Add note (and a shortcut),
   for things like "Mr. Yurt wrote x on the board". Shown under the line,
   small, with a nice UI (ux-planner, mockup first). Notes ARE included in
   Copy and Export (Ryan picked this), so Claude sees them. Store like
   markers (per line start, in recording.json), editable and deletable
   with Undo.
2. **Claude connection as a tool call.** Ryan wants Claude to call
   Verbatim itself (not copy and paste): a local MCP server so the Claude
   desktop app can list recordings, read a transcript (with notes and
   markers) and search. Claude first, ChatGPT later (it can use MCP too).
   Everything stays on the Mac. Note DECISIONS.md "no AI chat inside the
   app": this is Verbatim as a tool for Claude, not chat in Verbatim.

3. **Sidebar gear button** (small, do it first in the next chat): it shows
   in the blue app tint (`SettingsLink` with `.borderless` in
   `SidebarView`'s bottom bar). Ryan wants a better color (ink or
   secondary, like the other sidebar icons). And clicking it should pop UP
   a menu like Claude's account menu (his screenshot: Settings ⌘,, Usage,
   Language, Get help, Send feedback, ...), so things are one click away.
   No accounts in Verbatim, so pick what fits, for example: Settings ⌘,,
   Shortcuts, Check for Updates, What's new, Get help / Send feedback
   (opens GitHub issues), Copy Layout Details ⌃⌘L. Mockup first.
