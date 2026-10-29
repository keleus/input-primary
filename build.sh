#!/bin/zsh
# Build InputPrimary.app into ./build. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/InputPrimary.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

# Regenerate the icon with: swift Scripts/make-icon.swift Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
  Sources/main.swift -o "$APP/Contents/MacOS/InputPrimary"

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x InputPrimary || true
  rm -rf /Applications/InputPrimary.app
  cp -R "$APP" /Applications/
  open /Applications/InputPrimary.app
  echo "Installed to /Applications/InputPrimary.app"
fi
