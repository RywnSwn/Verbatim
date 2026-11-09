#!/bin/bash
# Builds Verbatim.app and zips it. Runs on macOS (GitHub Actions or a Mac
# with Command Line Tools). No Xcode project needed.
#
# Usage: scripts/build-app.sh [version] [build-number]
#   e.g. scripts/build-app.sh 0.1.7 7
set -euo pipefail

VERSION="${1:-0.1.0}"
BUILD="${2:-0}"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/build"
APP="$OUT/Verbatim.app"

echo "Building Verbatim $VERSION (build $BUILD)"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Verbatim"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Verbatim"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
    "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# Ad-hoc signature: Apple Silicon needs every app signed, and the mic
# permission is tied to it. Not notarized, so first open needs
# System Settings > Privacy & Security > Open Anyway.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose "$APP"

(cd "$OUT" && ditto -c -k --keepParent Verbatim.app Verbatim.zip)
echo "Done: $OUT/Verbatim.zip"
