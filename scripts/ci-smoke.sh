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
  sleep 2
}

toggle_sidebar() {
  # Click the real sidebar button in the toolbar, like Ryan does.
  osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$APP_PID"')
    set found to "no sidebar button found"
    repeat with e in (entire contents of window 1)
      try
        if class of e is button then
          set d to ""
          try
            set d to d & (description of e as text)
          end try
          try
            set d to d & " " & (title of e as text)
          end try
          try
            set d to d & " " & (help of e as text)
          end try
          if d contains "idebar" then
            set found to "clicked: " & d
            click e
            exit repeat
          end if
        end if
      end try
    end repeat
    return found
  end tell' || echo "toggle failed"
  sleep 3
}

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

launch
check "at launch"
osascript -e 'tell application "System Events" to get {position, size} of window 1 of (first process whose unix id is '"$APP_PID"')' || echo "no accessibility access"

for size in "1200 780" "900 600" "700 520" "700 420"; do
  set -- $size
  tag="$1x$2"
  resize "$1" "$2";      check "resize to $tag";            shot "$tag"
  toggle_sidebar;        check "sidebar toggle 1 at $tag";  shot "$tag-toggled"
  toggle_sidebar;        check "sidebar toggle 2 at $tag";  shot "$tag-toggled-back"
done

# Narrow with the sidebar forced open, then grow again.
resize 700 520; toggle_sidebar; check "open sidebar when narrow"; shot "narrow-sidebar-open"
resize 1200 780; check "grow again"; shot "grown-again"

kill "$APP_PID" 2>/dev/null || true
echo "----- app.log (tail) -----"; tail -20 "$OUT/app.log"
exit "$FAILED"
