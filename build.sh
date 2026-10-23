#!/bin/bash
# Builds Narrate.app, installs it in /Applications and opens it.
# Needs Xcode Command Line Tools:  xcode-select --install
#
# Install somewhere else by setting INSTALL_DIR, e.g.:
#   INSTALL_DIR=~/Applications ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

INSTALL_DIR="${INSTALL_DIR:-/Applications}"

APP=build/Narrate.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O main.swift -o "$APP/Contents/MacOS/Narrate" \
  -framework AppKit -framework AVFoundation -framework Speech -framework Carbon
cp Info.plist "$APP/Contents/Info.plist"

echo "Making the app icon…"
[ -f icon.png ] || swift makeicon.swift icon.png
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"

echo "Installing to $INSTALL_DIR…"
killall Narrate 2>/dev/null || true
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/Narrate.app"
cp -R "$APP" "$INSTALL_DIR/"
open "$INSTALL_DIR/Narrate.app"

echo "Done — Narrate is in your menu bar (speech-bubble icon)."
