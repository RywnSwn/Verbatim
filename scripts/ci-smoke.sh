#!/bin/bash
# Runs the built app on the CI Mac, resizes the window, toggles the sidebar and
# takes screenshots, so layout bugs and crashes show up before Ryan sees them.
# Usage: scripts/ci-smoke.sh <out-dir>   (after scripts/build-app.sh)
set -uo pipefail

OUT="${1:-smoke}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Verbatim.app/Contents/MacOS/Verbatim"
mkdir -p "$OUT"
FAILED=0
N=0

launch() {
  "$BIN" > "$OUT/app.log" 2>&1 &
  APP_PID=$!
  sleep 10
  osascript -e 'tell application "System Events" to set frontmost of (first process whose unix id is '"$APP_PID"') to true' || true
  sleep 1
}

alive() { kill -0 "$APP_PID" 2>/dev/null; }

shot() {
  N=$((N + 1))
  local name; name="$(printf '%02d' "$N")-$1.png"
  screencapture -x "$OUT/$name" || echo "screencapture failed"
  sips --resampleWidth 1100 "$OUT/$name" > /dev/null 2>&1 || true
  echo "shot $name"
}

resize() {
  osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$APP_PID"')
    set position of window 1 to {20, 40}
    set size of window 1 to {'"$1"', '"$2"'}
  end tell' || echo "resize failed"
  sleep "${RESIZE_WAIT:-2}"
}

# Our own sidebar button answers to ⌃⌘S (same code as clicking it).
click_at() {
  osascript -e 'tell application "System Events" to click at {'"$1"', '"$2"'}' > /dev/null || echo "click failed"
  sleep 0.5
}
toggle_sidebar() {
  osascript -e 'tell application "System Events" to keystroke "s" using {control down, command down}' || echo "toggle failed"
  sleep 1.5
}
show_sidebar() { toggle_sidebar; }
hide_sidebar() { toggle_sidebar; }

check() {
  if ! alive; then
    echo "::error::Verbatim died: $1"
    FAILED=1
    echo "----- app.log -----"; tail -40 "$OUT/app.log"
    sleep 8
    REPORT="$(ls -t ~/Library/Logs/DiagnosticReports/Verbatim* 2>/dev/null | head -1)"
    if [ -n "$REPORT" ]; then echo "----- $REPORT -----"; head -c 6000 "$REPORT"; fi
    launch
  fi
}

# Fake recordings and groups, so the sidebar has real rows like Ryan's.
seed() {
  local base="$HOME/Library/Application Support/Verbatim"
  local g1="11111111-1111-4111-8111-111111111111" g2="22222222-2222-4222-8222-222222222222"
  mkdir -p "$base/Recordings"
  cat > "$base/groups.json" <<JSON
{"formatVersion":1,"groups":[
 {"id":"$g1","name":"English 2026","icon":"book.closed","color":"blue","collapsed":false},
 {"id":"$g2","name":"World Studies 2026","icon":"globe.asia.australia","color":"green","collapsed":false},
 {"id":"33333333-3333-4333-8333-333333333333","name":"Math","icon":"x.squareroot","color":"green","collapsed":true},
 {"id":"44444444-4444-4444-8444-444444444444","name":"Science","icon":"atom","color":"purple","collapsed":true}]}
JSON
  # Few rows, like Ryan's real sidebar: one recording in two groups, one in Recents.
  local i
  for i in 1 2 3; do
    local id="aaaaaaaa-aaaa-4aaa-8aaa-00000000000$i" group="null"
    [ "$i" -eq 1 ] && group="\"$g1\""
    [ "$i" -eq 2 ] && group="\"$g2\""
    mkdir -p "$base/Recordings/$id"
    cat > "$base/Recordings/$id/recording.json" <<JSON
{"formatVersion":1,"id":"$id","title":"Anansi and the sky god, part $i","createdAt":"2026-11-0${i}T03:05:00Z",
 "endedAt":"2026-11-0${i}T03:52:00Z","state":"stopped","sampleRate":16000,"samples":45120000,"events":[],
 "audioDeletedAt":"2026-11-0${i}T04:00:00Z","groupID":$group,"notes":[{"time":5.0,"text":"On the board: Anansi = trickster"}]}
JSON
  done
  # One transcript, so the Claude connector has something to read.
  cat > "$base/Recordings/aaaaaaaa-aaaa-4aaa-8aaa-000000000001/live.json" <<JSON
{"formatVersion":1,"engines":["Parakeet"],"voiceNames":{"0":"Mr. Yurt"},"lines":[
 {"start":1.0,"end":4.0,"text":"Okay, books open to page forty one please.","voice":0},
 {"start":5.0,"end":9.0,"text":"Today we carry on with Anansi and the sky god.","voice":0},
 {"start":10.0,"end":14.0,"text":"Is the quiz on Friday?","voice":1}]}
JSON
}

# The Claude connector: Verbatim started with --mcp answers Claude's questions
# on stdin/stdout (see Sources/Verbatim/Connector). No window, read only.
mcp_check() {
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_recordings","arguments":{}}}' \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_transcript","arguments":{"recording":"part 1"}}}' \
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"search_transcripts","arguments":{"query":"QUIZ friday"}}}' \
    '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"read_transcript","arguments":{"recording":"anansi"}}}' \
    '{"jsonrpc":"2.0","id":7,"method":"nope"}' \
    | "$BIN" --mcp > "$OUT/mcp.txt" 2> "$OUT/mcp-err.txt"
  echo "----- connector answers -----"; cut -c1-900 "$OUT/mcp.txt"; cat "$OUT/mcp-err.txt"
  local lines; lines="$(wc -l < "$OUT/mcp.txt" | tr -d ' ')"
  if [ "$lines" != "7" ]; then echo "::error::Connector gave $lines answers, wanted 7"; FAILED=1; fi
  grep -q '"protocolVersion":"2025-06-18"' "$OUT/mcp.txt" || { echo "::error::Connector: no initialize answer"; FAILED=1; }
  grep -q '"name":"search_transcripts"' "$OUT/mcp.txt" || { echo "::error::Connector: tools missing"; FAILED=1; }
  grep -q 'Mr. Yurt: Today we carry on with Anansi' "$OUT/mcp.txt" || { echo "::error::Connector: transcript not read"; FAILED=1; }
  grep -q 'Speaker 1: Is the quiz on Friday' "$OUT/mcp.txt" || { echo "::error::Connector: search found nothing"; FAILED=1; }
  grep -q '(Note: On the board: Anansi = trickster)' "$OUT/mcp.txt" || { echo "::error::Connector: note missing"; FAILED=1; }
  grep -q '3 recordings match' "$OUT/mcp.txt" || { echo "::error::Connector: unclear name not handled"; FAILED=1; }
  grep -q '"code":-32601' "$OUT/mcp.txt" || { echo "::error::Connector: unknown method not refused"; FAILED=1; }
}

seed
mcp_check
# No "update ready" bar, so the window can be as short as Ryan's.
defaults write com.rywnswn.verbatim checkForUpdates -bool false
# A mini window size saved by an older build, like on Ryan's Mac. 0.1.150
# crashed opening the mini window with this (sizes fought until it crashed).
defaults write com.rywnswn.verbatim "NSWindow Frame VerbatimMiniWindow" "16 560 330 300 0 0 1440 875 "
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' || true
launch
check "at launch"
osascript -e 'tell application "System Events" to get {position, size} of window 1 of (first process whose unix id is '"$APP_PID"')' || echo "no accessibility access"

# Wide but short, like Ryan's window (about 1000 x 495): the sidebar's top
# and bottom must stay inside the window.
for size in "1000 400" "1000 540" "1000 600" "940 400"; do
  set -- $size
  resize "$1" "$2";  check "resize to $1x$2";  shot "short-$1x$2"
  osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$APP_PID"')
    set out to "window " & (size of window 1 as text)
    repeat with e in (entire contents of window 1)
      try
        if class of e is in {scroll area, outline, splitter group, group} then
          set {x, y} to position of e
          set {w, h} to size of e
          set out to out & linefeed & (class of e as text) & " y=" & y & " h=" & h & " x=" & x & " w=" & w
        end if
      end try
    end repeat
    return out
  end tell' | head -40
done

# The app's own layout report (Help > Copy Layout Details). The split view
# (sidebar + main area) must be exactly as tall as the window. On Ryan's Mac
# it was 692 pt in a 552 pt window. Checked right away and again once the
# "copied" message bar is showing, at two window heights.
layout_check() {
  : > "$OUT/app.log"
  osascript -e 'tell application "System Events" to keystroke "l" using {control down, command down}' || true
  sleep 2
  local win split
  win="$(grep -a -m1 "^  frame=" "$OUT/app.log" | sed -E 's/.* h([0-9]+) contentLayoutRect.*/\1/')"
  split="$(grep -a -m1 "NavigationSplitRepresentable" "$OUT/app.log" | sed -E 's/.* h([0-9]+) .*/\1/')"
  echo "layout check ($1): window height $win, split view height $split"
  grep -a -E "NavigationSplitRepresentable|HostingScrollView|OutlineListRepresentable|DraggingDestinationView" "$OUT/app.log" | cut -c1-170
  if [ -z "$win" ] || [ "$win" != "$split" ]; then
    echo "::error::Split view is not the window's height ($1): window $win, split $split"
    FAILED=1
  fi
}
for size in "1000 400" "960 620"; do
  set -- $size
  resize "$1" "$2"
  layout_check "$1x$2"
  layout_check "$1x$2 with the message bar"
  shot "layout-$1x$2-with-bar"
done

# The mini window (⇧⌘M): top left, floating. No empty strip above its first row.
osascript -e 'tell application "System Events" to keystroke "m" using {shift down, command down}' || echo "mini toggle failed"
sleep 2
check "mini window shown"
shot "mini-idle"
osascript -e 'tell application "System Events" to keystroke "m" using {shift down, command down}' || true
sleep 1

# Design pass: the Settings window (pages down the left), General then Look.
osascript -e 'tell application "System Events" to keystroke "," using {command down}' || true
sleep 3
check "open Settings"
shot "settings-general"
osascript -e 'tell application "System Events" to key code 125' || true
sleep 1.5
shot "settings-look"
osascript -e 'tell application "System Events" to key code 125' || true
sleep 1.5
shot "settings-transcription"
osascript -e 'tell application "System Events" to key code 125' || true
osascript -e 'tell application "System Events" to key code 125' || true
osascript -e 'tell application "System Events" to key code 125' || true
sleep 1.5
shot "settings-claude"
osascript -e 'tell application "System Events" to keystroke "w" using {command down}' || true
sleep 1

# A window that comes back shorter than the app's minimum (a frame saved by an
# older build, or macOS tiling). Ryan's window was like this: about 490 tall.
osascript -e 'tell application "System Events" to keystroke "q" using {command down}' || true
sleep 3
kill "$APP_PID" 2>/dev/null || true
echo "----- saved window frames -----"
defaults read com.rywnswn.verbatim | grep "NSWindow Frame" || echo "none saved"
defaults read com.rywnswn.verbatim | grep "NSWindow Frame" | sed -E 's/^ *"([^"]+)" = "([^"]+)";/\1|\2/' | while IFS='|' read -r key value; do
  set -- $value
  defaults write com.rywnswn.verbatim "$key" "20 250 1000 470 $5 $6 $7 $8 "
done
defaults read com.rywnswn.verbatim | grep "NSWindow Frame" || true
# Design pass: the other look (solid sidebar, paper cards) on the relaunch.
defaults write com.rywnswn.verbatim sidebarLook -string solid
defaults write com.rywnswn.verbatim rowLook -string cards
launch
check "relaunch with a short saved frame"
osascript -e 'tell application "System Events" to get {position, size} of window 1 of (first process whose unix id is '"$APP_PID"')' || true
shot "restored-short"

kill "$APP_PID" 2>/dev/null || true
echo "----- app.log (tail) -----"; tail -20 "$OUT/app.log"
exit "$FAILED"
