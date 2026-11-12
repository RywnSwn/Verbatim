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
 "audioDeletedAt":"2026-11-0${i}T04:00:00Z","groupID":$group}
JSON
  done
}

seed
# No "update ready" bar, so the window can be as short as Ryan's.
defaults write com.rywnswn.verbatim checkForUpdates -bool false
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

# The app's own layout report (Help > Copy Layout Details), to compare with Ryan's.
resize 1000 560
osascript -e 'tell application "System Events" to keystroke "l" using {control down, command down}' || true
sleep 2
echo "----- layout details -----"; grep -A200 "^Verbatim " "$OUT/app.log" | head -150

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
launch
check "relaunch with a short saved frame"
osascript -e 'tell application "System Events" to get {position, size} of window 1 of (first process whose unix id is '"$APP_PID"')' || true
shot "restored-short"

kill "$APP_PID" 2>/dev/null || true
echo "----- app.log (tail) -----"; tail -20 "$OUT/app.log"
exit "$FAILED"
