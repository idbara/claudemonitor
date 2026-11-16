# Claude Monitor

Aplikasi **menu bar macOS** yang menampilkan **kuota langganan Claude** Anda secara langsung — sama seperti yang ditampilkan perintah `/usage` di Claude Code, tetapi selalu terlihat di menu bar.

Data diambil langsung dari Anthropic sebagai **persentase pemakaian** (utilization), jadi bukan estimasi biaya. Anda bisa melihat sekilas seberapa dekat Anda dengan batas sesi 5 jam dan batas mingguan tanpa membuka terminal.

---

## Fitur

- **Multi-akun otomatis** — semua akun Claude Code di Mac ini terdeteksi sendiri, termasuk yang dijalankan dengan `CLAUDE_CONFIG_DIR=~/.claude-xxx` (lihat **Multi-akun**).
- **Rekomendasi ★** — akun dengan sisa limit terbanyak ditandai ★; klik barisnya untuk menyalin perintah `CLAUDE_CONFIG_DIR=… claude`.
- **Label menu bar** ringkas: `5h 38%` untuk satu akun, atau `★abati 12%` (akun yang disarankan) bila ada beberapa akun.
- **Berjalan di background** — tanpa ikon Dock, dengan opsi **Buka saat login**.
- **Popover** berisi satu baris per akun (bar 5 jam + 7 hari); chevron membuka meter lengkap:
  - **Session (5 jam)** — `five_hour`
  - **Weekly (7 hari)** — `seven_day`
  - **Weekly Sonnet (7 hari)** — `seven_day_sonnet`
  - **Weekly Opus (7 hari)** — `seven_day_opus` *(tersembunyi bila tidak ada pemakaian)*
- Tiap meter menampilkan **persentase** dan **hitung mundur reset** ("reset dalam Xj Ym").
- Tiap baris menampilkan nama akun dan badge plan (mis. **Max**).
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

Hasil build adalah **`Claude Monitor.app`** (di folder `Build/Products/Debug` pada DerivedData). Aplikasi ini hanya tampil di **menu bar** (tanpa ikon Dock, `LSUIElement`) — tidak ada jendela utama.

> Tidak ada test target di proyek ini. Verifikasi dilakukan lewat build yang sukses dan membandingkan angka dengan `/usage` Claude Code atau `curl` (lihat **Verifikasi**).

### Membuat installer (.dmg)

```bash
./make-dmg.sh
```

Script mem-build versi **Release** lalu mengemasnya menjadi `dist/Claude Monitor.dmg` (berisi app + alias `Applications` untuk drag-install). App di-*ad-hoc sign* (tanpa Developer ID/notarization), jadi di Mac lain Gatekeeper mungkin memblokir — klik kanan app → **Open**, atau jalankan `xattr -dr com.apple.quarantine "/Applications/Claude Monitor.app"`.

---

## Penggunaan

1. Jalankan **Claude Monitor**. Ikon Claude (sunburst) muncul di menu bar dengan teks `5h NN%` (atau `★akun NN%`).
2. **Saat pertama kali**, macOS menampilkan prompt untuk **tiap akun** (satu item Keychain per akun):
   > *"Claude Monitor" wants to use the "Claude Code-credentials…" keychain item.*

   Klik **Always Allow** agar aplikasi bisa membaca token (cukup sekali per akun).
3. **Klik ikon** di menu bar untuk membuka popover.
   - **Klik baris akun** → perintah untuk memakai akun itu disalin ke clipboard ("Disalin ✓"); tempel di terminal.
   - **Chevron** di kanan baris → buka meter lengkap (5 jam, 7 hari, Sonnet, Opus).
4. Bagian bawah popover:
   - **Buka saat login** — jalankan otomatis saat login macOS. Aktifkan dari app yang sudah di-install di `/Applications` (yang didaftarkan adalah lokasi app saat itu).
   - **Refresh** (⌘R) — ambil data terbaru sekarang.
   - **Quit** (⌘Q) — keluar dari aplikasi.

### Multi-akun

Claude Code menyimpan token akun default di item Keychain `Claude Code-credentials`. Bila dijalankan dengan `CLAUDE_CONFIG_DIR=<folder>`, tokennya disimpan di item terpisah `Claude Code-credentials-<8 hex pertama sha256(path absolut folder)>`.

Claude Monitor membaca daftar item tersebut (tanpa membaca tokennya), lalu mencocokkannya dengan folder `~/.claude*` di home Anda — mis. `~/.claude-abati` → akun **abati**. Item yang foldernya sudah tidak ada diabaikan, dan item dengan akun yang sama (uuid profil sama) digabung menjadi satu baris.

- **★ Rekomendasi** = akun dengan sisa limit terbanyak, dihitung `100 − max(5 jam, 7 hari)`. Hanya muncul bila ≥ 2 akun punya data; tidak ada ★ bila semua sudah penuh.
- **⚠ token kedaluwarsa** = token akun itu sudah lewat masa berlakunya karena lama tidak dipakai. Jalankan `claude` di akun itu (salin perintahnya dari baris) — Claude Code akan menyegarkan tokennya, dan monitor ikut terbarui. Monitor **tidak pernah** memakai refresh token sendiri, supaya login Claude Code tidak rusak.
- Hanya folder langsung di `$HOME` yang dipindai.

### Membaca angkanya

- Angka persen = **utilization** dari Anthropic (0–100%). Makin tinggi = makin dekat ke batas.
- "reset dalam Xj Ym" = perkiraan waktu jendela kuota tersebut ter-reset.
- Meter **Weekly Opus** hanya muncul bila ada pemakaian Opus pada minggu berjalan.

### Pesan status

| Tampilan | Arti |
|---|---|
| `Memuat…` | Sedang mengambil data pertama kali. |
| `⚠ token kedaluwarsa — jalankan claude di akun ini` | Token akun lewat masa berlaku atau ditolak (401). Jalankan `claude` di akun itu. |
| `Dibatasi sementara oleh Anthropic — mencoba lagi…` | Kena rate limit; akan retry otomatis. |
| `Tidak menemukan/baca kredensial Claude Code` | Keychain belum berisi token, atau izin ditolak. |
| `Tidak bisa terhubung ke Anthropic` | Masalah jaringan. |

---

## Cara Kerja

```
Keychain ("Claude Code-credentials", "Claude Code-credentials-<hash>", …)
        │  AccountDiscovery: cocokkan hash ↔ ~/.claude*  →  [Account]
        │  accessToken (OAuth) per akun
        ▼
   QuotaClient ──HTTP GET──▶ https://api.anthropic.com/api/oauth/usage
        │                                     └─▶ /api/oauth/profile (nama, email, plan, uuid)
        ▼
   AccountStore (@MainActor): refresh berurutan, gabung duplikat, pilih ★  ──▶  MenuBarExtra UI
```

- **`Credentials.swift`** — membaca daftar item Keychain `Claude Code-credentials*` (atribut saja) dan token OAuth per item (`claudeAiOauth.accessToken`, `expiresAt`) lewat Security framework. `refreshToken` tidak pernah disentuh.
- **`Account.swift`** — `AccountDiscovery`: mencocokkan item Keychain dengan folder `~/.claude*` lewat hash path.
- **`AccountMath.swift`** — logika murni: nama item Keychain dari path, label, perintah peluncuran, penggabungan duplikat, rekomendasi ★, label menu bar.
- **`QuotaClient.swift`** — `GET` async ke endpoint Anthropic dengan header `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`. Memetakan 401/403 → perlu login, 429 → rate limited.
- **`QuotaUsage.swift` / `Profile.swift`** — model `Decodable` untuk respons kuota & profil.
- **`ProfileCache.swift`** — menyimpan profil (uuid, nama, email, plan) per item Keychain di `UserDefaults`, supaya akun dengan token kedaluwarsa tetap punya nama.
- **`AccountStore.swift`** — `ObservableObject` yang menemukan akun, me-refresh tiap akun **berurutan** (timer 5 menit, saat popover muncul, dan manual), memetakan error per akun, menggabungkan duplikat, dan memilih ★.
- **`LoginItem.swift`** — toggle "Buka saat login" lewat `SMAppService.mainApp`.
- **`ClaudeMonitorApp.swift`** — `MenuBarExtra` + tampilan popover (`QuotaPopover`, satu baris per akun).

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
- Token tidak pernah ditulis ke disk oleh aplikasi. Yang disimpan hanya **profil akun** (uuid, nama, email, status plan) di `UserDefaults` aplikasi (`~/Library/Preferences/id.misindo.ClaudeMonitor.plist`) untuk menamai akun yang tokennya kedaluwarsa.
- Aplikasi **tidak pernah** memakai refresh token atau menulis ke item Keychain Claude Code.
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

`five_hour` / `seven_day` / `seven_day_sonnet` harus sama dengan yang ditampilkan aplikasi. Untuk akun lain, ganti `-s "Claude Code-credentials"` dengan item akun tersebut (mis. `-s "Claude Code-credentials-c6b43821"`; daftar lengkap: `security dump-keychain | grep -o '"svce"<blob>="Claude Code[^"]*"' | sort -u`).

Logika murni (hash nama item, label, penggabungan, ★, label menu bar) dicek lewat program kecil, karena proyek tidak punya test target:

```bash
swiftc ClaudeMonitor/AccountMath.swift ClaudeMonitor/Account.swift ClaudeMonitor/Credentials.swift ClaudeMonitor/Profile.swift ClaudeMonitor/ProfileCache.swift ClaudeMonitor/QuotaUsage.swift ClaudeMonitor/QuotaClient.swift ClaudeMonitor/AccountStore.swift Checks/main.swift -o "$TMPDIR/am-checks" && "$TMPDIR/am-checks"
```

Hasil yang diharapkan: `ALL CHECKS PASSED`.

---

## Troubleshooting

- **Ikon/teks tidak berubah setelah rebuild** — instance lama masih berjalan. Keluarkan dulu (`Quit`/`killall "Claude Monitor"`), lalu jalankan build terbaru.
- **Sering "Dibatasi sementara"** — endpoint kuota dibatasi ketat. Aplikasi sudah polling jarang (5 menit) dan menahan permintaan bertumpuk; hindari menekan Refresh berkali-kali.
- **"⚠ token kedaluwarsa"** — token akun itu kedaluwarsa/ditolak. Jalankan `claude` di akun tersebut (klik barisnya untuk menyalin perintah); bila masih ditolak, login ulang di Claude Code. Aplikasi ini tidak mengelola refresh OAuth sendiri.
- **Akun tidak muncul** — folder config-nya harus berada langsung di home (`~/.claude-xxx`) dan Claude Code harus pernah login dengan folder itu.
- **Prompt Keychain tidak muncul / ditolak** — buka **Keychain Access**, cari item `Claude Code-credentials…`, dan pastikan "Claude Monitor" diizinkan mengaksesnya.

---

## Batasan (di luar cakupan saat ini)

Refresh token OAuth mandiri, grafik historis, tampilan `extra_usage`/kredit, dan notifikasi saat mendekati limit belum diimplementasikan.

---

## Struktur Proyek

```
ClaudeMonitor/                 sumber Swift (lihat "Cara Kerja")
ClaudeMonitor/Assets.xcassets  AppIcon + ikon menu bar (ClaudeLogo)
Checks/main.swift              program cek logika murni (dikompilasi dengan swiftc)
docs/superpowers/specs/        dokumen desain
docs/superpowers/plans/        rencana implementasi
CLAUDE.md                      panduan untuk Claude Code di repo ini
```

> Catatan riwayat: versi awal aplikasi ini mem-parsing log lokal Claude Code (`~/.claude/projects/**/*.jsonl`) untuk mengestimasi biaya. Pendekatan itu telah digantikan oleh endpoint kuota resmi; dokumen `2026-05-30-usage-integration*` di `docs/` tetap disimpan sebagai catatan sejarah.

---

## Lisensi

Proyek pribadi. Logo dan merek "Claude" adalah milik Anthropic.
