#!/bin/bash
# Signs the app inside an unsigned archive ad hoc, with its entitlements, so that the export step keeps
# them when it re-signs for the App Store. The archive is built unsigned (see testflight.yml), and an
# unsigned app has no entitlements for the export to carry over.
#   presign.sh ARCHIVE ENTITLEMENTS   (APPLE_TEAM_ID must be set)
set -euo pipefail
ARCHIVE="$1"; TEMPLATE="$2"
APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "::error::No app in $ARCHIVE"; exit 1; }
if [ -f "$APP/Contents/Info.plist" ]; then PLIST="$APP/Contents/Info.plist"; NESTED="$APP/Contents/Frameworks"; else PLIST="$APP/Info.plist"; NESTED="$APP/Frameworks"; fi
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$PLIST")
ENT="$(mktemp -d)/entitlements.plist"
sed -e "s/\$(TeamIdentifierPrefix)/${APPLE_TEAM_ID}./g" -e "s/\$(CFBundleIdentifier)/${BUNDLE}/g" "$TEMPLATE" > "$ENT"
plutil -lint "$ENT"
# nested code first: codesign won't sign a bundle whose frameworks are unsigned
if [ -d "$NESTED" ]; then
  find "$NESTED" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0 | while IFS= read -r -d '' f; do
    codesign --force --sign - --timestamp=none "$f"
  done
fi
codesign --force --sign - --timestamp=none --entitlements "$ENT" "$APP"
echo "Signed $APP ad hoc with:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - || codesign -d --entitlements :- "$APP"
