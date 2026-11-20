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
  # How long launch took (see LaunchTimer), kept for comparing builds.
  echo "----- launch $1 -----" | tee -a "$OUT/launch.txt"
  grep -a "^LAUNCH:" "$OUT/app.log" | tee -a "$OUT/launch.txt"
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
    launch "after a crash"
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

# 200 old classes with long transcripts (about 500 lines each, like a long
# lesson), in a folded group, to measure how launch copes with a full year.
# No audio, so nothing gets transcribed or shrunk.
seed_many() {
  local base="$HOME/Library/Application Support/Verbatim"
  python3 - "$base" <<'PY'
import json, os, random, sys, uuid
base = sys.argv[1]
groups_path = os.path.join(base, "groups.json")
groups = json.load(open(groups_path))
gid = "55555555-5555-4555-8555-555555555555"
groups["groups"].append({"id": gid, "name": "Old classes", "icon": "archivebox", "color": "ink", "collapsed": True})
json.dump(groups, open(groups_path, "w"))
random.seed(7)
vocab = ("the story tells us how a small spider became the keeper of every tale in the village and why "
         "people still listen when the teacher reads it out loud to the class before the bell rings today").split()
def live():
    lines, t = [], 0.0
    for n in range(500):
        count = random.randint(18, 32)
        words = [random.choice(vocab) for _ in range(count)]
        starts = [round(t + k * 0.38, 2) for k in range(count)]
        end = round(t + count * 0.38, 2)
        lines.append({"start": round(t, 2), "end": end, "text": " ".join(words).capitalize() + ".",
                      "words": starts, "voice": random.choice([0, 0, 0, 1, 2])})
        t = end + 0.6
    return {"formatVersion": 1, "engines": ["Parakeet"], "lines": lines, "speakersFound": True}
for i in range(200):
    rid = str(uuid.UUID(int=0xbbbbbbbb_bbbb_4bbb_8bbb_000000000000 + i))
    folder = os.path.join(base, "Recordings", rid.upper())
    os.makedirs(folder, exist_ok=True)
    day = 1 + i % 28
    info = {"formatVersion": 1, "id": rid.upper(), "title": "Old class %d" % (i + 1),
            "createdAt": "2026-%02d-%02dT03:05:00Z" % (1 + i // 28, day),
            "endedAt": "2026-%02d-%02dT03:52:00Z" % (1 + i // 28, day),
            "state": "stopped", "sampleRate": 16000, "samples": 45120000, "events": [],
            "audioDeletedAt": "2026-%02d-%02dT04:00:00Z" % (1 + i // 28, day), "groupID": gid}
    json.dump(info, open(os.path.join(folder, "recording.json"), "w"))
    json.dump(live(), open(os.path.join(folder, "live.json"), "w"), indent=2, sort_keys=True)
PY
  echo "seeded 200 old classes: $(du -sh "$base/Recordings" | cut -f1) in Recordings"
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
seed_many
# No "update ready" bar, so the window can be as short as Ryan's.
defaults write com.rywnswn.verbatim checkForUpdates -bool false
# A mini window size saved by an older build, like on Ryan's Mac. 0.1.150
# crashed opening the mini window with this (sizes fought until it crashed).
defaults write com.rywnswn.verbatim "NSWindow Frame VerbatimMiniWindow" "16 560 330 300 0 0 1440 875 "
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' || true
launch "first"
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

# Open a recording (texts are read when opened, not at launch): its lines
# must show. Click "Anansi and the sky god, part 1", the first row in the
# sidebar (window is 960x620 at 20,40 here). Typing into ⌘K didn't arrive
# on the CI Mac.
click_at 160 218
sleep 2
check "open a recording"
shot "opened-recording"

# The sidebar never resizes the window (Ryan, 2026-11-20: it grew wider each
# time he opened it). 760 and up: it opens inside the window. Below: it slides
# over the transcript. Open and close a few times; the width must not change.
win_width() {
  osascript -e 'tell application "System Events" to get item 1 of (size of window 1 of (first process whose unix id is '"$APP_PID"'))' 2>/dev/null
}
same_width() {
  local w; w="$(win_width)"
  echo "window width after $2: $w (wanted $1)"
  if [ "$w" != "$1" ]; then echo "::error::Sidebar changed the window width ($2): $w, wanted $1"; FAILED=1; fi
}
for width in 800 700; do
  resize "$width" 600; check "resize to $width"
  shot "sidebar-$width-start"
  for round in 1 2 3; do
    toggle_sidebar; check "sidebar toggle $width #$round"
    [ "$round" = 1 ] && shot "sidebar-$width-toggled-once"
    toggle_sidebar; check "sidebar toggle back $width #$round"
    same_width "$width" "toggle at $width, round $round"
  done
done
# 700 wide: floating sidebar. Esc and a click on the dimmed transcript close it.
toggle_sidebar; shot "sidebar-700-floating"
osascript -e 'tell application "System Events" to key code 53' || true
sleep 1; shot "sidebar-700-after-esc"
toggle_sidebar
click_at 600 400
sleep 1; shot "sidebar-700-after-click-outside"
same_width 700 "floating sidebar"
check "floating sidebar"
resize 960 620; check "back to 960"
sleep 1; shot "sidebar-960-back"

# Copy All (⇧⌘C) and Export as Markdown read the same text: check the
# speaker names are in it (Ryan, 2026-11-19: "a copy doesn't show the speaker").
pbcopy < /dev/null
osascript -e 'tell application "System Events" to keystroke "c" using {shift down, command down}' || true
sleep 1
pbpaste > "$OUT/copy-all.txt"
echo "copy all:"; cat "$OUT/copy-all.txt"
if ! grep -q "Mr. Yurt" "$OUT/copy-all.txt"; then
  echo "::error::Copy All has no speaker names"
  FAILED=1
fi

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
echo "----- text index -----" | tee -a "$OUT/launch.txt"
INDEX="$HOME/Library/Application Support/Verbatim/text-index.json"
if [ -f "$INDEX" ]; then
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); e=d["entries"]; print("%d entries, %d with lines, %d bytes" % (len(e), sum(1 for v in e.values() if v["facts"]["hasLines"]), len(open(sys.argv[1]).read())))' "$INDEX" | tee -a "$OUT/launch.txt"
else
  echo "no text-index.json" | tee -a "$OUT/launch.txt"
fi
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
launch "second"
check "relaunch with a short saved frame"
osascript -e 'tell application "System Events" to get {position, size} of window 1 of (first process whose unix id is '"$APP_PID"')' || true
shot "restored-short"

kill "$APP_PID" 2>/dev/null || true
echo "----- app.log (tail) -----"; tail -20 "$OUT/app.log"
exit "$FAILED"
