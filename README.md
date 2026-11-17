<div align="center">

<img src="ClaudeMonitor/Assets.xcassets/AppIcon.appiconset/icon_128@2x.png" width="128" alt="Ikon Claude Monitor">

# Claude Monitor

**Sisa limit semua akun Claude Anda, selalu terlihat di menu bar — dan pindah akun otomatis saat limit habis.**

![macOS 26.5+](https://img.shields.io/badge/macOS-26.5%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)
![Python](https://img.shields.io/badge/cc-Python%203-3776AB?logo=python&logoColor=white)
![Tanpa dependency](https://img.shields.io/badge/dependency-nol-brightgreen)

</div>

---

Pernah sedang asyik coding lalu Claude Code tiba-tiba berhenti karena **limit 5 jam habis**? Atau punya beberapa akun, tapi tidak tahu mana yang masih punya sisa — dan mana yang sisanya sebentar lagi hangus?

**Claude Monitor** menampilkan pemakaian kuota langganan Claude Anda (data yang sama dengan `/usage` di Claude Code) langsung dari Anthropic, untuk **semua akun sekaligus**. Pasangannya, **`cc`**, menjalankan Claude Code dan **pindah ke akun lain secara otomatis saat limit habis — percakapan tetap berlanjut**.

```
 ┌─ menu bar ──────────────────────────────┐
 │                       ✳ ★kerja 18%   🔋  │
 └─────────────────────────────────────────┘
 ┌─ Claude Monitor ──────────────────────┐
 │ ★ kerja   Max  5h ▓▓░░░ 18%  7d 41%   │
 │   Bara · reset dalam 0j 40m       ›   │
 │ ───────────────────────────────────── │
 │   default Max  5h ▓▓▓▓░ 78%  7d 23%   │
 │   Bara · reset dalam 3j 12m       ›   │
 │ ───────────────────────────────────── │
 │   lama         ⚠ token kedaluwarsa    │
 │ ───────────────────────────────────── │
 │ Diperbarui 08:12:05                   │
 │ ☑ Buka saat login                     │
 │ [Refresh]                    [Quit]   │
 └───────────────────────────────────────┘
```

## ✨ Sorotan

| | |
|---|---|
| 📊 **Angka asli, bukan tebakan** | Persentase pemakaian diambil langsung dari endpoint kuota Anthropic — sama dengan `/usage`. |
| 👥 **Semua akun, tanpa setup** | Setiap akun Claude Code di Mac ini (termasuk yang memakai `CLAUDE_CONFIG_DIR`) terdeteksi sendiri. |
| ★ **Tahu akun mana yang dipakai dulu** | ★ menandai akun yang sisanya **paling cepat hangus** — sisa ≥ 20% dan reset 5 jam paling dekat. Habiskan dulu sebelum terbuang. |
| 🔁 **Pindah akun otomatis** | `cc` mendeteksi limit, menutup claude, lalu melanjutkan **sesi yang sama** di akun berikutnya. |
| 🔔 **Notifikasi tepat waktu** | Diberi tahu saat limit hampir habis, saat sisa akan hangus, saat akun penuh akan bisa dipakai lagi, dan saat limit sudah reset. |
| 📋 **Satu klik ganti akun** | Klik baris akun → perintah untuk memakainya tersalin ke clipboard. |
| 🌙 **Diam di background** | Tanpa ikon Dock, opsi **Buka saat login**, refresh tiap 5 menit. |
| 🔒 **Token tetap milik Claude Code** | Token hanya dikirim ke `api.anthropic.com`, tidak pernah ditulis ke disk, dan refresh token tidak pernah disentuh. |

---

## 🚀 Mulai cepat

**1. Build & jalankan app**

```bash
open ClaudeMonitor.xcodeproj    # lalu ⌘R
```

atau buat installer `.dmg` dan seret ke **Applications**:

```bash
./make-dmg.sh                   # hasil: dist/Claude Monitor.dmg
```

**2. Izinkan akses Keychain** — saat pertama kali, macOS bertanya sekali per akun:

> *"Claude Monitor" wants to use the "Claude Code-credentials…" keychain item.*

Klik **Always Allow**. Selesai — ikon ✳ dengan `5h NN%` muncul di menu bar.

**3. (Opsional) Pasang `cc` untuk pindah akun otomatis**

```bash
python3 scripts/cc.py setup     # tutup semua sesi claude dulu
cc                              # pakai seperti `claude`
```

> **Butuh:** macOS 26.5+, Xcode, dan Claude Code yang sudah login dengan akun langganan (Pro/Max). Tidak perlu API key — app memakai login Claude Code yang sudah ada.

---

## 👥 Banyak akun

Setiap akun Claude Code tinggal di foldernya sendiri: `~/.claude` (akun **default**) dan `~/.claude-<nama>` untuk akun lain. Claude Monitor menemukannya sendiri — nama folder jadi label akun (`~/.claude-kerja` → **kerja**).

Cara termudah mengelola akun adalah lewat `cc`:

```bash
cc account new kerja      # buat ~/.claude-kerja, samakan konfigurasinya dengan default, lalu login (browser)
cc account list           # daftar akun, status, dan sisa limit
cc account remove kerja   # logout + pindahkan foldernya ke Tong Sampah (ketik ulang nama untuk konfirmasi)
```

Akun baru muncul di popover pada refresh berikutnya (klik **Always Allow** di prompt Keychain-nya).

### ★ Akun mana yang dipakai dulu?

Prinsipnya: **habiskan dulu limit yang paling cepat hangus.**

1. Sisa dihitung `100 − max(5 jam, 7 hari)` — jadi limit mingguan tetap diperhitungkan.
2. Di antara akun dengan sisa **≥ 20%**, yang **reset 5 jamnya paling dekat** menang. Bila resetnya berselisih < 15 menit, yang sisanya lebih besar menang.
3. Akun yang window 5 jamnya belum berjalan ada di belakang — sisanya tidak akan hangus.
4. Tidak ada yang ≥ 20%? Dipilih sisa terbesar. Semua penuh? Tidak ada ★.

> Contoh: **kerja** sisa 60%, reset 40 menit lagi · **default** sisa 90%, reset 4 jam lagi → ★ **kerja**. Habiskan dulu 60% itu sebelum hangus; default tetap utuh untuk nanti.

Aturan yang sama dipakai `cc` saat memilih akun.

---

## 🔁 `cc` — pindah akun otomatis

```console
$ cc
╭──────────────────────────────────────────────╮
│ ✻ Claude Code                                │
╰──────────────────────────────────────────────╯
> refactor modul pembayaran …
  ⎿ 5-hour limit reached ∙ resets 10:00
cc: limit di default → lanjut di kerja
╭──────────────────────────────────────────────╮
│ ✻ Claude Code                                │
╰──────────────────────────────────────────────╯
> lanjutkan
  ⏺ Melanjutkan refactor modul pembayaran …
```

**Cara kerjanya:** saat sebuah giliran gagal karena limit, hook `StopFailure` milik Claude Code memberi tahu `cc`. `cc` menutup claude, memilih akun berikutnya (aturan ★), lalu menjalankan `claude --resume <sesi yang sama> "lanjutkan"` di akun itu — di folder proyek yang sama.

```bash
cc                        # mulai di akun ★
cc --account kerja        # mulai di akun tertentu
cc --model opus           # argumen lain diteruskan ke claude
cc status                 # daftar akun + sisa limit
```

Ingin pindah akun **secara manual**? Keluar dari claude (`/exit`), lalu di folder proyek yang sama:

```bash
cc --account kerja --continue     # lanjutkan sesi terakhir di folder ini
cc --account kerja --resume       # pilih dari daftar sesi
```

<details>
<summary><b>Apa yang dilakukan <code>cc setup</code>?</b></summary>

- Di setiap folder akun (`~/.claude-xxx` yang punya login di Keychain), entri `projects`, `skills`, `plugins`, `rules`, `plans`, `file-history`, `agents`, `commands`, `settings.json`, dan `CLAUDE.md` dijadikan **symlink ke `~/.claude`** — riwayat sesi, skill, plugin, dan pengaturan jadi sama di semua akun. Itulah yang membuat akun mana pun bisa melanjutkan sesi mana pun. Login dan `.claude.json` tetap per akun.
- Isi lama folder akun digabung ke `~/.claude` **tanpa menimpa** (versi `~/.claude` menang); aslinya dipindah ke `~/.claude-switch/backup/<akun>-<waktu>/`. **Tidak ada yang dihapus.**
- Menambahkan hook `StopFailure` (matcher `rate_limit`) → `~/.local/bin/cc hook` ke `~/.claude/settings.json` (dicadangkan dulu), dan memasang `cc` ke `~/.local/bin/cc`.
- Menampilkan rencananya dulu dan meminta konfirmasi `y/N`. Aman dijalankan ulang — jalankan lagi setelah memperbarui `cc.py`.

> Karena `settings.json` ikut dibagi, pengaturan seperti `model` di `~/.claude/settings.json` berlaku untuk semua akun.

</details>

<details>
<summary><b>Detail perilaku <code>cc</code></b></summary>

- Akun berikutnya dipilih dari `~/Library/Application Support/ClaudeMonitor/accounts.json` yang ditulis Claude Monitor setiap refresh (tanpa token/email): akun `ok` menurut aturan ★, lalu akun yang tokennya kedaluwarsa (biasanya hanya karena lama tak dipakai — menjalankan claude di sana menyegarkannya). Bila data monitor tidak ada atau lebih tua 15 menit, `cc` memakai folder akun yang sudah tertaut.
- Akun yang baru kena limit dicatat di `~/.claude-switch/limited.json` sampai waktu reset-nya.
- Flag `--model`, `--permission-mode`, `--dangerously-skip-permissions`, dan `--add-dir` ikut dibawa saat pindah akun.
- Semua akun penuh → `cc: semua akun penuh — reset paling cepat HH:MM`, lalu keluar. Pindah akun maksimal sebanyak jumlah akun per sesi.
- Sesi `claude` biasa tidak terpengaruh — hook tidak melakukan apa-apa di luar `cc`.
- Giliran pertama setelah pindah akun sedikit lebih mahal karena prompt cache dibangun ulang.
- `cc` tidak pernah membaca token; setup hanya mengecek *nama* item Keychain.
- `cc account remove` menolak akun `default` dan folder yang bukan akun (mis. `~/.claude-mem`).

</details>

---

## 🔔 Notifikasi

Untuk setiap akun, window **5 jam** dan **mingguan**:

| Notifikasi | Kapan | Contoh |
|---|---|---|
| Hampir habis | saat melewati 80%, lalu 95% | *default · 5 jam* — Sudah 82% terpakai — reset 1j 10m lagi |
| Akan bisa dipakai lagi | 15 menit sebelum reset, bila sudah ≥ 80% | *default · 5 jam* — Hampir penuh (96%) — reset 15 menit lagi |
| Sisa akan hangus | 30 menit sebelum reset, bila sisa ≥ 20% | *kerja · 5 jam* — Sisa 60% hangus dalam 30 menit — pakai sekarang |
| Sudah reset | tepat saat reset, bila tadinya ≥ 80% | *default · 5 jam* — Limit 5 jam sudah reset — kembali 100% |

- Notifikasi berbasis waktu **dijadwalkan ke macOS** sehingga datang tepat waktu — bahkan saat app sedang ditutup — dan dijadwal ulang setiap refresh agar angkanya selalu segar.
- Setiap notifikasi dikirim **sekali** per window; window baru (setelah reset) mulai dari awal.
- Matikan/nyalakan lewat checkbox **Notifikasi** di bawah popover. Izin notifikasi diminta sekali saat pertama kali.

---

## 🧭 Membaca popover

- **Klik baris akun** → perintah untuk memakai akun itu tersalin (`Disalin ✓`).
- **Chevron ›** → meter lengkap: Session (5 jam), Weekly (7 hari), Weekly Sonnet, Weekly Opus — masing-masing dengan hitung mundur reset.
- Angka persen = **utilization** dari Anthropic (0–100%). Makin tinggi, makin dekat ke batas.
- Label menu bar: `5h 38%` untuk satu akun, atau `★kerja 18%` (akun yang disarankan) bila ada beberapa.

| Tampilan | Arti |
|---|---|
| `Memuat…` | Sedang mengambil data pertama kali. |
| `⚠ token kedaluwarsa — jalankan claude di akun ini` | Token akun lewat masa berlaku atau ditolak. Jalankan `claude` di akun itu (salin perintahnya dari baris). |
| `Dibatasi sementara oleh Anthropic — mencoba lagi…` | Kena rate limit; akan dicoba lagi otomatis. |
| `Tidak menemukan/baca kredensial Claude Code` | Belum ada login di Keychain, atau izin ditolak. |
| `Tidak bisa terhubung ke Anthropic` | Masalah jaringan. |

---

## 🔒 Privasi & keamanan

- Token OAuth **hanya** dikirim ke `api.anthropic.com`, pemilik sah token tersebut.
- Token **tidak pernah ditulis ke disk**. Yang disimpan hanya profil akun (uuid, nama, email, plan) di `UserDefaults` app, agar akun yang tokennya kedaluwarsa tetap punya nama. `accounts.json` untuk `cc` tidak berisi token maupun email.
- App **tidak pernah** memakai refresh token atau menulis ke item Keychain Claude Code — refresh token berputar, dan memakainya bisa merusak login Claude Code.
- **App Sandbox dimatikan** (`ENABLE_APP_SANDBOX = NO`): app tersandbox tidak bisa membaca item Keychain milik Claude Code.

---

<details>
<summary><b>🛠 Cara kerja (untuk developer)</b></summary>

```
Keychain ("Claude Code-credentials", "Claude Code-credentials-<hash>", …)
        │  AccountDiscovery: cocokkan hash ↔ ~/.claude*  →  [Account]
        │  accessToken (OAuth) per akun
        ▼
   QuotaClient ──HTTP GET──▶ https://api.anthropic.com/api/oauth/usage
        │                                     └─▶ /api/oauth/profile (nama, email, plan, uuid)
        ▼
   AccountStore (@MainActor): refresh berurutan, gabung duplikat, pilih ★
        ├──▶ MenuBarExtra UI
        └──▶ accounts.json ──▶ cc (scripts/cc.py)
```

Claude Code menyimpan login akun default di item Keychain `Claude Code-credentials`, dan login untuk `CLAUDE_CONFIG_DIR=<folder>` di `Claude Code-credentials-<8 hex pertama sha256(path absolut folder)>`. App membaca daftar item itu (atribut saja), mencocokkannya dengan folder `~/.claude*`, membuang item yang foldernya sudah tidak ada, dan menggabungkan item dengan akun yang sama (uuid profil).

| File | Tugas |
|---|---|
| `Credentials.swift` | Daftar item Keychain `Claude Code-credentials*` dan token per item (`accessToken`, `expiresAt`). |
| `Account.swift` | `AccountDiscovery`: item Keychain ↔ folder `~/.claude*`. |
| `AccountMath.swift` | Logika murni: nama item dari path, label, perintah peluncuran, penggabungan, ★, label menu bar. |
| `QuotaClient.swift` | `GET` ke `oauth/usage` & `oauth/profile` (401/403 → perlu login, 429 → rate limited). |
| `QuotaUsage.swift`, `Profile.swift` | Model respons. |
| `ProfileCache.swift` | Profil per akun di `UserDefaults`. |
| `AccountStore.swift` | Refresh berurutan tiap 5 menit / saat popover dibuka / manual; error per akun; ★. |
| `AccountsExport.swift` | Menulis `accounts.json` untuk `cc`. |
| `NotificationPlanner.swift` | Logika murni notifikasi: apa yang dikirim sekarang & yang dijadwalkan. |
| `LimitNotifier.swift` | Mengirim/menjadwalkan notifikasi (UserNotifications), checkbox Notifikasi. |
| `LoginItem.swift` | "Buka saat login" lewat `SMAppService`. |
| `ClaudeMonitorApp.swift` | `MenuBarExtra` + popover. |
| `scripts/cc.py` | Pembungkus `claude`: pindah akun otomatis, `setup`, `account new/remove/list`. |

**Contoh respons endpoint kuota:**

```json
{
  "five_hour":        { "utilization": 38.0, "resets_at": "..." },
  "seven_day":        { "utilization": 53.0, "resets_at": "..." },
  "seven_day_sonnet": { "utilization": 2.0,  "resets_at": "..." },
  "seven_day_opus":   null
}
```

</details>

<details>
<summary><b>✅ Verifikasi & tes</b></summary>

Bandingkan angka di popover dengan respons mentah endpoint:

```bash
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")

curl -sS https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "anthropic-version: 2023-06-01" | python3 -m json.tool
```

Untuk akun lain, ganti `-s "Claude Code-credentials"` dengan item akun tersebut. Daftar item: `security dump-keychain | grep -o '"svce"<blob>="Claude Code[^"]*"' | sort -u`.

Proyek ini tidak punya test target Xcode; logika murninya dicek dengan dua perintah:

```bash
# Logika Swift (★, penggabungan, label, accounts.json, notifikasi) → ALL CHECKS PASSED
swiftc ClaudeMonitor/AccountMath.swift ClaudeMonitor/Account.swift ClaudeMonitor/Credentials.swift ClaudeMonitor/Profile.swift ClaudeMonitor/ProfileCache.swift ClaudeMonitor/QuotaUsage.swift ClaudeMonitor/QuotaClient.swift ClaudeMonitor/AccountStore.swift ClaudeMonitor/AccountsExport.swift ClaudeMonitor/NotificationPlanner.swift ClaudeMonitor/LimitNotifier.swift Checks/main.swift -o "$TMPDIR/am-checks" && "$TMPDIR/am-checks"

# cc → OK
python3 -m unittest discover -s scripts -p 'test_*.py'
```

</details>

<details>
<summary><b>🚀 Rilis (dmg otomatis lewat GitHub Actions)</b></summary>

Setiap kali sebuah **release dipublikasikan** di GitHub, workflow [`release-dmg.yml`](.github/workflows/release-dmg.yml) mem-build `Claude-Monitor-<versi>.dmg` di runner macOS GitHub dan melampirkannya ke release tersebut. Versi diambil dari tag (`v1.2.0` → `1.2.0`).

App di CI ditandatangani dengan sertifikat **yang sama** seperti build lokal ("Claude Monitor Self-Signed"), sehingga izin Keychain "Always Allow" pengguna tetap berlaku setelah update.

**Setup sekali (dilakukan sendiri, karena berisi private key):**

1. **Keychain Access** → *My Certificates* → klik kanan **Claude Monitor Self-Signed** → **Export…** → simpan sebagai `cm.p12` dengan password.
2. Simpan ke secrets repo:
   ```bash
   base64 -i cm.p12 | gh secret set MACOS_CERT_P12
   gh secret set MACOS_CERT_PASSWORD      # ketik password .p12 saat diminta
   rm cm.p12
   ```

**Membuat rilis:**

```bash
gh release create v1.0.0 --generate-notes
```

Beberapa menit kemudian `Claude-Monitor-1.0.0.dmg` muncul di halaman release. Untuk membangun ulang dmg sebuah release yang sudah ada: tab **Actions** → *Release DMG* → *Run workflow* → isi tag.

Build lokal dengan versi: `VERSION=1.2.0 BUILD_NUMBER=7 ./make-dmg.sh`; cek hasilnya dengan `scripts/verify-dmg.sh dist/Claude-Monitor-1.2.0.dmg 1.2.0 7`.

</details>

<details>
<summary><b>🩹 Troubleshooting</b></summary>

- **Ikon/teks tidak berubah setelah rebuild** — instance lama masih berjalan. `killall "Claude Monitor"`, lalu jalankan build terbaru.
- **Sering "Dibatasi sementara"** — endpoint kuota dibatasi ketat. App sudah polling jarang (5 menit); hindari menekan Refresh berkali-kali.
- **"⚠ token kedaluwarsa"** — jalankan `claude` di akun itu (klik barisnya untuk menyalin perintah); bila masih ditolak, login ulang.
- **Akun tidak muncul** — folder config harus langsung di home (`~/.claude-xxx`) dan pernah login. Paling mudah: `cc account new <nama>`.
- **Prompt Keychain tidak muncul / ditolak** — buka **Keychain Access**, cari `Claude Code-credentials…`, izinkan "Claude Monitor".
- **`.dmg` diblokir Gatekeeper di Mac lain** — app ditandatangani sertifikat self-signed (bukan Developer ID, tanpa notarization). Klik kanan app → **Open**, atau `xattr -dr com.apple.quarantine "/Applications/Claude Monitor.app"`.
- **Notifikasi tidak muncul** — cek mode **Focus/Jangan Ganggu**: selama aktif, macOS menahan banner (notifikasinya tetap ada di Pusat Notifikasi). Izinkan *Claude Monitor* di pengaturan Focus tersebut, atau cek **Pengaturan Sistem › Notifikasi › Claude Monitor**.
- **"Buka saat login" menunjuk app yang salah** — login item mendaftarkan lokasi app saat itu; aktifkan dari salinan di `/Applications`.

</details>

---

## 🗺 Belum ada (ide berikutnya)

Grafik riwayat pemakaian · tampilan `extra_usage`/kredit · refresh token mandiri (sengaja tidak, demi keamanan login Claude Code).

## 📁 Struktur proyek

```
ClaudeMonitor/                 sumber Swift
ClaudeMonitor/Assets.xcassets  AppIcon + ikon menu bar (ClaudeLogo)
Checks/main.swift              cek logika Swift (dikompilasi dengan swiftc)
scripts/cc.py                  pindah akun otomatis (+ test_cc.py)
make-dmg.sh                    pembuat installer .dmg (VERSION/BUILD_NUMBER opsional)
scripts/verify-dmg.sh          cek versi & tanda tangan sebuah .dmg
.github/workflows/             release → .dmg otomatis
docs/superpowers/              dokumen desain & rencana implementasi
CLAUDE.md                      panduan untuk Claude Code di repo ini
```

<sub>Versi awal app ini mengestimasi biaya dari log lokal Claude Code; pendekatan itu digantikan endpoint kuota resmi (catatannya tetap di `docs/`). Pendekatan multi-akun `cc` terinspirasi Troupe (ADR-0004). Proyek pribadi — logo dan merek "Claude" milik Anthropic.</sub>
