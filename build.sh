#!/bin/zsh
# Builds ClickPaste.app with the Swift compiler already on this Mac. No dependencies, nothing installed.
#   ./build.sh           -> build/ClickPaste.app
#   ./build.sh install   -> also copies it to /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP=build/ClickPaste.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/main.swift \
  -o "$APP/Contents/MacOS/ClickPaste"

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x ClickPaste 2>/dev/null || true
  rm -rf /Applications/ClickPaste.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/ClickPaste.app"
fi
