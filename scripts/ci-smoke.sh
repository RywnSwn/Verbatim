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

# The sidebar button is not exposed to accessibility, so click where it is.
# Window sits at {20, 40}. Sidebar hidden: button at x 143. Shown: just inside
# the sidebar's right edge (224 for a 220 pt sidebar, 264 for 260 pt).
click_at() {
  osascript -e 'tell application "System Events" to click at {'"$1"', '"$2"'}' > /dev/null || echo "click failed"
  sleep 0.5
}
show_sidebar() { click_at 143 65; sleep 1; }
hide_sidebar() { click_at 224 65; click_at 264 65; sleep 1; }

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
 {"id":"$g2","name":"World Studies 2026","icon":"globe.asia.australia","color":"green","collapsed":false}]}
JSON
  local i
  for i in 1 2 3 4 5 6 7 8 9; do
    local id="aaaaaaaa-aaaa-4aaa-8aaa-00000000000$i" group="null"
    [ "$i" -le 3 ] && group="\"$g1\""
    [ "$i" -ge 4 ] && [ "$i" -le 5 ] && group="\"$g2\""
    mkdir -p "$base/Recordings/$id"
    cat > "$base/Recordings/$id/recording.json" <<JSON
{"formatVersion":1,"id":"$id","title":"Anansi and the sky god, part $i","createdAt":"2026-11-0${i}T03:05:00Z",
 "endedAt":"2026-11-0${i}T03:52:00Z","state":"stopped","sampleRate":16000,"samples":45120000,"events":[],
 "audioDeletedAt":"2026-11-0${i}T04:00:00Z","groupID":$group}
JSON
  done
}

seed
launch
check "at launch"
osascript -e 'tell application "System Events" to get {position, size} of window 1 of (first process whose unix id is '"$APP_PID"')' || echo "no accessibility access"

# Wide: sidebar starts shown.
for size in "1200 780" "900 600"; do
  set -- $size
  tag="$1x$2"
  resize "$1" "$2";  check "resize to $tag";         shot "$tag"
  hide_sidebar;      check "hide sidebar at $tag";   shot "$tag-hidden"
  show_sidebar;      check "show sidebar at $tag";   shot "$tag-shown"
done

# Narrow: the sidebar hides itself; open it by hand like Ryan did.
for size in "800 600" "700 520" "700 420"; do
  set -- $size
  tag="$1x$2"
  resize "$1" "$2";  check "resize to $tag";         shot "$tag"
  show_sidebar;      check "show sidebar at $tag";   shot "$tag-shown"
  hide_sidebar;      check "hide sidebar at $tag";   shot "$tag-hidden"
  show_sidebar;      check "show sidebar again at $tag"
  resize 1200 780;   check "grow with sidebar open from $tag"; shot "$tag-grown"
done

# Sweep the window height through the point where the start screen switches
# between "fits" and "scrolls", toggling the sidebar at each step.
for w in 900 1000 760; do
  h=380
  while [ "$h" -le 600 ]; do
    RESIZE_WAIT=1 resize "$w" "$h" > /dev/null;  check "sweep resize ${w}x${h}"
    if [ "$w" -ge 860 ]; then
      hide_sidebar; check "sweep hide sidebar at ${w}x${h}"
      show_sidebar; check "sweep show sidebar at ${w}x${h}"
    else
      show_sidebar; check "sweep show sidebar at ${w}x${h}"
      hide_sidebar; check "sweep hide sidebar at ${w}x${h}"
    fi
    h=$((h + 5))
  done
  shot "sweep-$w-done"
done

# A recording open in the main area (click the first row), then the sidebar button.
resize 1000 700; show_sidebar
click_at 110 190; sleep 2;  check "open a recording";               shot "recording-open"
hide_sidebar;               check "hide sidebar with recording";    shot "recording-sidebar-hidden"
show_sidebar;               check "show sidebar with recording";    shot "recording-sidebar-shown"
resize 700 520;             check "narrow with recording";          shot "recording-narrow"
show_sidebar;               check "show sidebar, narrow recording"; shot "recording-narrow-shown"

kill "$APP_PID" 2>/dev/null || true
echo "----- app.log (tail) -----"; tail -20 "$OUT/app.log"
exit "$FAILED"
