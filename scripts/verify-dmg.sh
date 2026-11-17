#!/usr/bin/env bash
#
# verify-dmg.sh — pastikan .dmg berisi Claude Monitor dengan versi yang benar
# dan ditandatangani sertifikat "Claude Monitor Self-Signed" (bukan ad-hoc).
#
# Pemakaian:  scripts/verify-dmg.sh <file.dmg> <versi> [build]
#
set -euo pipefail

DMG="${1:?pemakaian: verify-dmg.sh <file.dmg> <versi> [build]}"
WANT_VERSION="${2:?versi wajib}"
WANT_BUILD="${3:-}"

[ -f "$DMG" ] || { echo "!! Tidak ada: $DMG"; exit 1; }

MNT="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" > /dev/null
trap 'hdiutil detach "$MNT" -quiet || true; rmdir "$MNT" 2>/dev/null || true' EXIT

APP="$MNT/Claude Monitor.app"
[ -d "$APP" ] || { echo "!! App tidak ada di dalam dmg"; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist")"
REQ="$(codesign -d -r- "$APP" 2>&1)"

fail=0
[ "$VERSION" = "$WANT_VERSION" ] || { echo "!! Versi $VERSION, seharusnya $WANT_VERSION"; fail=1; }
if [ -n "$WANT_BUILD" ] && [ "$BUILD" != "$WANT_BUILD" ]; then
  echo "!! Build $BUILD, seharusnya $WANT_BUILD"; fail=1
fi
if ! grep -q 'certificate leaf = H"' <<< "$REQ"; then
  echo "!! Tidak ditandatangani sertifikat self-signed (ad-hoc?):"; echo "$REQ"; fail=1
fi
[ "$fail" = 0 ] && echo "OK: versi $VERSION (build $BUILD), ditandatangani sertifikat self-signed"
exit "$fail"
