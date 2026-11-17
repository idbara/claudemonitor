#!/usr/bin/env bash
#
# set-signing-secrets.sh — ekspor identitas "Claude Monitor Self-Signed" dari
# keychain login lalu simpan ke secrets GitHub (MACOS_CERT_P12 + MACOS_CERT_PASSWORD)
# untuk workflow rilis. File .p12 hanya dibuat di folder sementara lalu dihapus.
#
# Pemakaian (dari folder repo):  scripts/set-signing-secrets.sh
#
# macOS akan meminta izin (password login) untuk mengekspor kunci privat.
#
set -euo pipefail

NAME="Claude Monitor Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Pastikan hanya identitas ini yang akan ikut terekspor.
IDENTITIES="$(security find-identity "$KEYCHAIN" | grep -E '^\s+[0-9]+\)' | sort -u || true)"
COUNT="$(printf '%s\n' "$IDENTITIES" | grep -c ')' || true)"
if [ "$COUNT" != 1 ] || ! grep -q "\"$NAME\"" <<< "$IDENTITIES"; then
  echo "!! Keychain login berisi $COUNT identitas; script ini hanya aman bila satu-satunya adalah \"$NAME\"."
  echo "   Ekspor manual lewat Keychain Access (README › Rilis)."
  exit 1
fi

read -rsp "Buat password untuk file .p12: " PW; echo
read -rsp "Ulangi password: " PW2; echo
[ -n "$PW" ] && [ "$PW" = "$PW2" ] || { echo "!! Password kosong atau tidak sama."; exit 1; }

umask 077
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Mengekspor \"$NAME\" (setujui dialog macOS)…"
security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$PW" -o "$TMP/cm.p12"
[ -s "$TMP/cm.p12" ] || { echo "!! Ekspor gagal / dibatalkan."; exit 1; }

echo "==> Menyimpan secrets ke GitHub…"
base64 -i "$TMP/cm.p12" | gh secret set MACOS_CERT_P12
printf '%s' "$PW" | gh secret set MACOS_CERT_PASSWORD

echo "==> Selesai. File .p12 sementara sudah dihapus."
gh secret list
