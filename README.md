# Claude Monitor

Aplikasi **menu bar macOS** yang menampilkan **kuota langganan Claude** Anda secara langsung — sama seperti yang ditampilkan perintah `/usage` di Claude Code, tetapi selalu terlihat di menu bar.

Data diambil langsung dari Anthropic sebagai **persentase pemakaian** (utilization), jadi bukan estimasi biaya. Anda bisa melihat sekilas seberapa dekat Anda dengan batas sesi 5 jam dan batas mingguan tanpa membuka terminal.

---

## Fitur

- **Label menu bar** ringkas menampilkan pemakaian sesi 5 jam, mis. `5h 38%`.
- **Popover** berisi meter (progress bar) untuk tiap jendela kuota:
  - **Session (5 jam)** — `five_hour`
  - **Weekly (7 hari)** — `seven_day`
  - **Weekly Sonnet (7 hari)** — `seven_day_sonnet`
  - **Weekly Opus (7 hari)** — `seven_day_opus` *(tersembunyi bila tidak ada pemakaian)*
- Tiap meter menampilkan **persentase** dan **hitung mundur reset** ("reset dalam Xj Ym").
- **Header** menampilkan nama akun, email, dan badge plan (mis. **Max**).
- **Refresh otomatis** tiap 5 menit, saat popover dibuka, dan via tombol manual.
- Aman terhadap **rate limit**: data lama dipertahankan saat gagal sesaat, dan retry menghormati `Retry-After`.

---

## Persyaratan

- **macOS 26.5** atau lebih baru.
- **Xcode** (untuk build) — proyek murni Xcode, tanpa dependency eksternal.
- **Claude Code sudah login** dengan akun langganan (Pro/Max) di Mac yang sama. Token OAuth-nya disimpan di Keychain dan dipakai bersama oleh aplikasi ini.

> Aplikasi ini **tidak** meminta API key. Ia memakai ulang token login Claude Code yang sudah ada.

---

## Build & Jalankan

```bash
# Build (Debug) dari terminal
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build

# Atau buka di Xcode lalu tekan ⌘R
open ClaudeMonitor.xcodeproj
```

Hasil build adalah **`Claude Monitor.app`** (di folder `Build/Products/Debug` pada DerivedData). Aplikasi ini hanya tampil di **menu bar** (dan Dock) — tidak ada jendela utama.

> Tidak ada test target di proyek ini. Verifikasi dilakukan lewat build yang sukses dan membandingkan angka dengan `/usage` Claude Code atau `curl` (lihat **Verifikasi**).

### Membuat installer (.dmg)

```bash
./make-dmg.sh
```

Script mem-build versi **Release** lalu mengemasnya menjadi `dist/Claude Monitor.dmg` (berisi app + alias `Applications` untuk drag-install). App di-*ad-hoc sign* (tanpa Developer ID/notarization), jadi di Mac lain Gatekeeper mungkin memblokir — klik kanan app → **Open**, atau jalankan `xattr -dr com.apple.quarantine "/Applications/Claude Monitor.app"`.

---

## Penggunaan

1. Jalankan **Claude Monitor**. Ikon Claude (sunburst) muncul di menu bar dengan teks `5h NN%`.
2. **Saat pertama kali**, macOS akan menampilkan prompt:
   > *"Claude Monitor" wants to use the "Claude Code-credentials" keychain item.*

   Klik **Always Allow** agar aplikasi bisa membaca token (cukup sekali).
3. **Klik ikon** di menu bar untuk membuka popover berisi meter kuota.
4. Tombol di bawah popover:
   - **Refresh** (⌘R) — ambil data terbaru sekarang.
   - **Quit** (⌘Q) — keluar dari aplikasi.

### Membaca angkanya

- Angka persen = **utilization** dari Anthropic (0–100%). Makin tinggi = makin dekat ke batas.
- "reset dalam Xj Ym" = perkiraan waktu jendela kuota tersebut ter-reset.
- Meter **Weekly Opus** hanya muncul bila ada pemakaian Opus pada minggu berjalan.

### Pesan status

| Tampilan | Arti |
|---|---|
| `Memuat…` | Sedang mengambil data pertama kali. |
| `Sesi kedaluwarsa — login ulang di Claude Code` | Token ditolak (401). Buka Claude Code dan login ulang. |
| `Dibatasi sementara oleh Anthropic — mencoba lagi…` | Kena rate limit; akan retry otomatis. |
| `Tidak menemukan/baca kredensial Claude Code` | Keychain belum berisi token, atau izin ditolak. |
| `Tidak bisa terhubung ke Anthropic` | Masalah jaringan. |

---

## Cara Kerja

```
Keychain ("Claude Code-credentials")
        │  accessToken (OAuth)
        ▼
   QuotaClient ──HTTP GET──▶ https://api.anthropic.com/api/oauth/usage
        │                                     └─▶ /api/oauth/profile (nama, email, plan)
        ▼
   QuotaUsage / Profile  ──▶  QuotaStore (@MainActor)  ──▶  MenuBarExtra UI
```

- **`Credentials.swift`** — membaca token OAuth Claude Code dari **Keychain** (item generic-password bernama `Claude Code-credentials`, field `claudeAiOauth.accessToken`) lewat Security framework.
- **`QuotaClient.swift`** — `GET` async ke endpoint Anthropic dengan header `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`. Memetakan 401/403 → perlu login, 429 → rate limited.
- **`QuotaUsage.swift` / `Profile.swift`** — model `Decodable` untuk respons kuota & profil.
- **`QuotaStore.swift`** — `ObservableObject` yang mengoordinasi refresh (timer 5 menit, saat popover muncul, dan manual) serta memetakan error ke status UI.
- **`ClaudeMonitorApp.swift`** — `MenuBarExtra` + tampilan popover (`QuotaPopover`).

### Endpoint kuota (respons)

```json
{
  "five_hour":        { "utilization": 38.0, "resets_at": "..." },
  "seven_day":        { "utilization": 53.0, "resets_at": "..." },
  "seven_day_sonnet": { "utilization": 2.0,  "resets_at": "..." },
  "seven_day_opus":   null
}
```

---

## Privasi & Keamanan

- Token OAuth **hanya** dikirim ke `api.anthropic.com` — pemilik sah token tersebut. Tidak dikirim ke pihak lain.
- Tidak ada token/PII yang disimpan di dalam repositori atau ditulis ke disk oleh aplikasi.
- **App Sandbox dimatikan** (`ENABLE_APP_SANDBOX = NO`). Ini wajib: aplikasi tersandbox tidak bisa membaca item Keychain milik aplikasi lain (Claude Code) maupun melakukan panggilan jaringan tanpa entitlement.

---

## Verifikasi

Bandingkan angka di popover dengan respons mentah endpoint yang sama:

```bash
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")

curl -sS https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "anthropic-version: 2023-06-01" | python3 -m json.tool
```

`five_hour` / `seven_day` / `seven_day_sonnet` harus sama dengan yang ditampilkan aplikasi.

---

## Troubleshooting

- **Ikon/teks tidak berubah setelah rebuild** — instance lama masih berjalan. Keluarkan dulu (`Quit`/`killall "Claude Monitor"`), lalu jalankan build terbaru.
- **Sering "Dibatasi sementara"** — endpoint kuota dibatasi ketat. Aplikasi sudah polling jarang (5 menit) dan menahan permintaan bertumpuk; hindari menekan Refresh berkali-kali.
- **"Sesi kedaluwarsa"** — token kedaluwarsa/ditolak. Buka Claude Code dan login ulang; aplikasi ini menyegarkan token dari Keychain secara otomatis (tidak mengelola refresh OAuth sendiri).
- **Prompt Keychain tidak muncul / ditolak** — buka **Keychain Access**, cari item `Claude Code-credentials`, dan pastikan "Claude Monitor" diizinkan mengaksesnya.

---

## Batasan (di luar cakupan saat ini)

Refresh token OAuth mandiri, grafik historis, tampilan `extra_usage`/kredit, dan notifikasi saat mendekati limit belum diimplementasikan.

---

## Struktur Proyek

```
ClaudeMonitor/                 sumber Swift (lihat "Cara Kerja")
ClaudeMonitor/Assets.xcassets  AppIcon + ikon menu bar (ClaudeLogo)
docs/superpowers/specs/        dokumen desain
docs/superpowers/plans/        rencana implementasi
CLAUDE.md                      panduan untuk Claude Code di repo ini
```

> Catatan riwayat: versi awal aplikasi ini mem-parsing log lokal Claude Code (`~/.claude/projects/**/*.jsonl`) untuk mengestimasi biaya. Pendekatan itu telah digantikan oleh endpoint kuota resmi; dokumen `2026-05-30-usage-integration*` di `docs/` tetap disimpan sebagai catatan sejarah.

---

## Lisensi

Proyek pribadi. Logo dan merek "Claude" adalah milik Anthropic.
