#!/bin/bash
# Builds Verbatim.app and Verbatim.zip without Xcode (Command Line Tools is enough).
# Usage: scripts/build-app.sh [version] [build-number]
set -euo pipefail

VERSION="${1:-0.0.0}"
BUILD="${2:-0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
APP="$OUT/Verbatim.app"

cd "$ROOT"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Verbatim"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Verbatim"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Support/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# Ad-hoc signature: required to run on Apple Silicon, not a paid Apple ID.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose "$APP"

ditto -c -k --keepParent "$APP" "$OUT/Verbatim.zip"
echo "Built $APP (version $VERSION, build $BUILD)"
