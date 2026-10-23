#!/bin/bash
# Builds Narrate.app, installs it in /Applications and opens it.
# Needs Xcode Command Line Tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

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

echo "Installing to /Applications…"
killall Narrate 2>/dev/null || true
rm -rf /Applications/Narrate.app
cp -R "$APP" /Applications/
open /Applications/Narrate.app

echo "Done — Narrate is in your menu bar (speech-bubble icon)."
