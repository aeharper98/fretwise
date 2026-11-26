#!/bin/bash
# Prints the entitlements of the signed app inside an exported .ipa or .pkg (or an .app) and fails if a
# required one is missing. A key written as ?key only warns.
#   check-entitlements.sh FILE KEY [?KEY ...]
set -euo pipefail
FILE="$1"; shift
WORK=$(mktemp -d)
case "$FILE" in
  *.ipa) unzip -q "$FILE" -d "$WORK/x"; APP=$(find "$WORK/x/Payload" -maxdepth 1 -name '*.app' | head -1) ;;
  *.pkg) pkgutil --expand-full "$FILE" "$WORK/x"; APP=$(find "$WORK/x" -maxdepth 4 -type d -name '*.app' | head -1) ;;
  *) APP="$FILE" ;;
esac
[ -n "$APP" ] || { echo "::error::No app found in $FILE"; exit 1; }
codesign -d --entitlements - --xml "$APP" > "$WORK/ent.plist" 2>/dev/null || codesign -d --entitlements :- "$APP" > "$WORK/ent.plist"
echo "Entitlements of $(basename "$APP") in $(basename "$FILE"):"
plutil -p "$WORK/ent.plist"
status=0
for k in "$@"; do
  key="${k#\?}"
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$WORK/ent.plist" >/dev/null 2>&1; then
    if [ "$k" != "$key" ]; then echo "::warning::The signed app is missing $key"; else echo "::error::The signed app is missing $key"; status=1; fi
  fi
done
exit $status
