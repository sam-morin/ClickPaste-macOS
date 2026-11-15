#!/bin/zsh
# Builds ClickPaste.app with the Swift compiler already on this Mac. No dependencies, nothing installed.
#   ./build.sh           -> build/ClickPaste.app (ad-hoc signed)
#   ./build.sh install   -> also copies it to /Applications
#   ./build.sh release   -> Developer ID signed, notarized and stapled build/ClickPaste-<version>.zip
#                           Needs NOTARY_PROFILE (a `xcrun notarytool store-credentials` profile name).
#                           SIGN_ID defaults to the first "Developer ID Application" identity in the keychain.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/ClickPaste.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/main.swift \
  -o "$APP/Contents/MacOS/ClickPaste"

if [[ "${1:-}" != "release" ]]; then
  codesign --force --sign - "$APP" >/dev/null 2>&1
  echo "Built $APP"
fi

if [[ "${1:-}" == "install" ]]; then
  pkill -x ClickPaste 2>/dev/null || true
  rm -rf /Applications/ClickPaste.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/ClickPaste.app"
fi

if [[ "${1:-}" == "release" ]]; then
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile name}"
  SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}"
  [[ -n "$SIGN_ID" ]] || { echo "No Developer ID Application identity found" >&2; exit 1; }
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
  ZIP="build/ClickPaste-$VERSION.zip"

  # Notarization requires the hardened runtime and a secure timestamp.
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  echo "Signed with $SIGN_ID"

  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"

  # Re-zip so the download carries the stapled ticket and works offline.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
  echo "Built $ZIP"
fi
