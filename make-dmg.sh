#!/usr/bin/env bash
#
# make-dmg.sh — build Claude Monitor (Release) dan kemas jadi .dmg siap-install.
# Output: dist/Claude Monitor.dmg  (atau dist/Claude-Monitor-<VERSION>.dmg bila VERSION diisi)
#
# Pemakaian:  ./make-dmg.sh
#             VERSION=1.2.0 BUILD_NUMBER=7 ./make-dmg.sh   # dipakai workflow rilis
#
set -euo pipefail

PROJECT="ClaudeMonitor.xcodeproj"
SCHEME="ClaudeMonitor"
APP_NAME="Claude Monitor"     # = PRODUCT_NAME
VOL_NAME="Claude Monitor"     # nama volume saat dmg di-mount

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

DERIVED="$(mktemp -d)"
STAGE="$(mktemp -d)/root"
DIST="$ROOT/dist"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
if [ -n "$VERSION" ]; then
  OUT="$DIST/Claude-Monitor-${VERSION}.dmg"
else
  OUT="$DIST/${APP_NAME}.dmg"
fi

# Override versi hanya bila diisi (tanpa env = perilaku lama).
XC_OVERRIDES=()
[ -n "$VERSION" ] && XC_OVERRIDES+=("MARKETING_VERSION=$VERSION")
[ -n "$BUILD_NUMBER" ] && XC_OVERRIDES+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
mkdir -p "$DIST" "$STAGE"

cleanup() { rm -rf "$DERIVED" "$(dirname "$STAGE")"; }
trap cleanup EXIT

echo "==> Build Release…"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
      -derivedDataPath "$DERIVED" ${XC_OVERRIDES[@]+"${XC_OVERRIDES[@]}"} clean build > "$DERIVED/build.log" 2>&1; then
  echo "!! Build gagal. 20 baris terakhir:"; tail -20 "$DERIVED/build.log"; exit 1
fi

APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "!! Tidak menemukan $APP"; exit 1; }

echo "==> Kemas DMG…"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"     # untuk drag-to-install

rm -f "$OUT"
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT" > /dev/null

echo "==> Selesai:"
ls -lh "$OUT"
echo
echo "Catatan: app di-sign dgn sertifikat self-signed \"Claude Monitor Self-Signed\""
echo "  (tanpa Developer ID / notarization)."
echo "Di Mac lain, jika Gatekeeper memblokir: klik kanan app -> Open, atau"
echo "  xattr -dr com.apple.quarantine \"/Applications/${APP_NAME}.app\""
