# Quota Meters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ClaudeMonitor's local-log cost display with live subscription quota meters (session 5h, weekly 7d, weekly Sonnet, weekly Opus) fetched from Anthropic's `oauth/usage` endpoint using the OAuth token stored in the macOS Keychain.

**Architecture:** `Credentials` reads the Keychain token; `QuotaClient` does an async GET against `api.anthropic.com/api/oauth/usage` and decodes it into `QuotaUsage`; `QuotaStore` (`@MainActor ObservableObject`) coordinates refresh and publishes state; the `MenuBarExtra` UI renders one progress meter per window. The old log-parsing pipeline is deleted.

**Tech Stack:** Swift 5 / SwiftUI, macOS 26.5, Security framework (Keychain), `URLSession` async, `Codable`. No external dependencies.

**Testing note:** No test target (per spec). Verification per task = the app compiles via:
```bash
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build
```
Expected on success: ends with `** BUILD SUCCEEDED **`. Final task = run the app and cross-check the meters against a manual `curl` of the same endpoint.

**Reference — verified endpoint:** `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`. Returns `{ five_hour, seven_day, seven_day_sonnet, seven_day_opus, ... }` where each window is `{ "utilization": Double, "resets_at": String } | null`.

---

### Task 1: Disable App Sandbox

**Files:**
- Modify: `ClaudeMonitor.xcodeproj/project.pbxproj` (two `ENABLE_APP_SANDBOX = YES;` lines → `NO`)

Rationale: a sandboxed app cannot read another app's Keychain item or make outbound network calls without entitlements. We disable the sandbox.

- [ ] **Step 1: Flip both sandbox flags**

Replace every occurrence of `ENABLE_APP_SANDBOX = YES;` with `ENABLE_APP_SANDBOX = NO;` in `ClaudeMonitor.xcodeproj/project.pbxproj`. There are exactly two (Debug and Release configs). Use a precise replace; do not touch anything else in the file.

After editing, confirm:
```bash
grep -c "ENABLE_APP_SANDBOX = NO;" ClaudeMonitor.xcodeproj/project.pbxproj
grep -c "ENABLE_APP_SANDBOX = YES;" ClaudeMonitor.xcodeproj/project.pbxproj
```
Expected: first prints `2`, second prints `0`.

- [ ] **Step 2: Verify it still builds**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor.xcodeproj/project.pbxproj
git commit -m "build: disable App Sandbox (needed for Keychain + network access)"
```

---

### Task 2: Credentials reader

**Files:**
- Create: `ClaudeMonitor/Credentials.swift`

Reads the OAuth access token from the Keychain generic-password item whose service is `Claude Code-credentials`. The stored value is JSON: `{ "claudeAiOauth": { "accessToken": "...", "expiresAt": <ms>, ... }, ... }`.

- [ ] **Step 1: Create the file**

```swift
//
//  Credentials.swift
//  ClaudeMonitor
//

import Foundation
import Security

struct ClaudeCredentials {
    let accessToken: String
    let expiresAt: Date?
}

enum CredentialsError: Error {
    case notFound      // item / token tidak ada di Keychain
    case unreadable    // item ada tapi gagal di-decode
}

enum Credentials {
    private static let service = "Claude Code-credentials"

    /// Baca token OAuth Claude Code dari Keychain. Memicu prompt izin sekali.
    static func load() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialsError.notFound
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw CredentialsError.unreadable
        }
        var expires: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expires = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = oauth["expiresAt"] as? Int {
            expires = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return ClaudeCredentials(accessToken: token, expiresAt: expires)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/Credentials.swift
git commit -m "feat: read Claude Code OAuth token from Keychain"
```

---

### Task 3: QuotaUsage model

**Files:**
- Create: `ClaudeMonitor/QuotaUsage.swift`

Decodes the `oauth/usage` response. Each window is `{ "utilization": Double, "resets_at": String } | null`. `resets_at` is ISO-8601 with fractional seconds + timezone offset.

- [ ] **Step 1: Create the file**

```swift
//
//  QuotaUsage.swift
//  ClaudeMonitor
//

import Foundation

/// Satu window kuota (mis. 5 jam / 7 hari).
struct QuotaWindow: Decodable {
    let utilization: Double
    let resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try c.decodeIfPresent(Double.self, forKey: .utilization) ?? 0
        if let s = try c.decodeIfPresent(String.self, forKey: .resetsAt) {
            resetsAt = QuotaWindow.parseDate(s)
        } else {
            resetsAt = nil
        }
    }

    /// resets_at punya fractional seconds + offset, mis. "2026-05-30T17:50:01.019646+00:00".
    static func parseDate(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}

/// Hanya window yang kita pakai; sisanya di respons diabaikan.
struct QuotaUsage: Decodable {
    let fiveHour: QuotaWindow?
    let sevenDay: QuotaWindow?
    let sevenDaySonnet: QuotaWindow?
    let sevenDayOpus: QuotaWindow?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/QuotaUsage.swift
git commit -m "feat: add QuotaUsage decodable model"
```

---

### Task 4: Quota API client

**Files:**
- Create: `ClaudeMonitor/QuotaClient.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  QuotaClient.swift
//  ClaudeMonitor
//

import Foundation

enum QuotaClientError: Error {
    case unauthorized          // 401/403 — token ditolak
    case badResponse           // status non-2xx lain / body tak terbaca
    case network(Error)        // gangguan transport
}

enum QuotaClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Ambil kuota dari Anthropic memakai access token OAuth.
    static func fetch(accessToken: String) async throws -> QuotaUsage {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("ClaudeMonitor", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw QuotaClientError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw QuotaClientError.badResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw QuotaClientError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw QuotaClientError.badResponse
        }
        do {
            return try JSONDecoder().decode(QuotaUsage.self, from: data)
        } catch {
            throw QuotaClientError.badResponse
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/QuotaClient.swift
git commit -m "feat: add Anthropic oauth/usage API client"
```

---

### Task 5: Quota store

**Files:**
- Create: `ClaudeMonitor/QuotaStore.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  QuotaStore.swift
//  ClaudeMonitor
//

import Foundation
import Combine

enum QuotaState: Equatable {
    case loading
    case ok
    case needsLogin
    case error(String)
}

@MainActor
final class QuotaStore: ObservableObject {
    @Published var quota: QuotaUsage?
    @Published var state: QuotaState = .loading
    @Published var lastUpdated: Date?

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        if state != .loading { state = .loading }
        Task { [weak self] in
            do {
                let creds = try Credentials.load()
                let usage = try await QuotaClient.fetch(accessToken: creds.accessToken)
                self?.quota = usage
                self?.state = .ok
                self?.lastUpdated = Date()
            } catch CredentialsError.notFound {
                self?.state = .error("Tidak menemukan kredensial Claude Code")
            } catch CredentialsError.unreadable {
                self?.state = .error("Tidak bisa baca kredensial Claude Code")
            } catch QuotaClientError.unauthorized {
                self?.state = .needsLogin
            } catch QuotaClientError.network {
                self?.state = .error("Tidak bisa terhubung ke Anthropic")
            } catch {
                self?.state = .error("Gagal mengambil kuota")
            }
        }
    }
}
```

Note: the `Task` here is created on the `@MainActor` (the class is `@MainActor`), so `self?.…` assignments are already main-actor isolated. `Credentials.load()` is synchronous Keychain I/O; it is acceptable here because the call is fast and the first call may show a system prompt that must be on the main thread.

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`. If the compiler emits an actor-isolation ERROR, report it as BLOCKED with the exact text — do not redesign.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/QuotaStore.swift
git commit -m "feat: add QuotaStore with refresh + 60s timer"
```

---

### Task 6: Wire the UI

**Files:**
- Modify (full replace): `ClaudeMonitor/ClaudeMonitorApp.swift`

- [ ] **Step 1: Replace the entire file**

```swift
//
//  ClaudeMonitorApp.swift
//  ClaudeMonitor
//
//  Created by Bara Ramadhan on 30/05/26.
//

import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            QuotaPopover(store: store)
        } label: {
            Image(systemName: "cpu")
            Text(menuLabel)
        }
        .menuBarExtraStyle(.window)
    }

    /// Label menu bar = utilisasi window 5 jam, mis. "5h 26%".
    private var menuLabel: String {
        if let u = store.quota?.fiveHour?.utilization {
            return "5h \(Int(u.rounded()))%"
        }
        return ""
    }
}

/// Isi popover: satu meter per window kuota.
struct QuotaPopover: View {
    @ObservedObject var store: QuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kuota Claude")
                .font(.headline)
            Text("Langsung dari Anthropic (akun Max)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            switch store.state {
            case .loading where store.quota == nil:
                Text("Memuat…").foregroundColor(.secondary)
            case .needsLogin:
                Text("Sesi kedaluwarsa — login ulang di Claude Code")
                    .foregroundColor(.secondary)
            case .error(let msg):
                Text(msg).foregroundColor(.secondary)
            default:
                if let q = store.quota {
                    meter("Session (5 jam)", q.fiveHour)
                    meter("Weekly (7 hari)", q.sevenDay)
                    meter("Weekly Sonnet (7 hari)", q.sevenDaySonnet)
                    meter("Weekly Opus (7 hari)", q.sevenDayOpus)
                } else {
                    Text("Memuat…").foregroundColor(.secondary)
                }
            }

            Divider()
            if let updated = store.lastUpdated {
                Text("Diperbarui \(updated, format: .dateTime.hour().minute().second())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear { store.refresh() }
    }

    /// Tampilkan meter hanya bila window tidak nil.
    @ViewBuilder
    private func meter(_ title: String, _ window: QuotaWindow?) -> some View {
        if let w = window {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.subheadline)
                    Spacer()
                    Text("\(Int(w.utilization.rounded()))%")
                        .font(.subheadline).bold()
                }
                ProgressView(value: min(max(w.utilization, 0), 100), total: 100)
                if let reset = w.resetsAt {
                    Text("reset dalam \(Self.countdown(to: reset))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// "Xj Ym" sampai `date` (atau "<1m" / "sekarang").
    static func countdown(to date: Date) -> String {
        let secs = Int(date.timeIntervalSinceNow)
        if secs <= 0 { return "sekarang" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)j \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run the build command.
Expected: `** BUILD SUCCEEDED **`. A harmless pre-existing AppIntents.framework warning may appear; ignore it.

- [ ] **Step 3: Commit**

```bash
git add ClaudeMonitor/ClaudeMonitorApp.swift
git commit -m "feat: render quota meters in menu bar popover"
```

---

### Task 7: Delete the old log pipeline

**Files:**
- Delete: `ClaudeMonitor/UsageEntry.swift`, `ClaudeMonitor/Pricing.swift`, `ClaudeMonitor/LogParser.swift`, `ClaudeMonitor/UsageStats.swift`, `ClaudeMonitor/UsageStore.swift`

These types are no longer referenced (the UI now uses `QuotaStore`). Removing them keeps the codebase clean.

- [ ] **Step 1: Confirm they are unreferenced**

```bash
grep -rEl "UsageStore|UsageAggregator|LogParser|UsageEntry|Pricing|UsageStats|ModelUsage" ClaudeMonitor --include=*.swift
```
Expected: only the five files listed above appear (no reference from `ClaudeMonitorApp.swift` or the new Quota files). If any *other* file references them, STOP and report — do not delete.

- [ ] **Step 2: Delete the files**

```bash
git rm ClaudeMonitor/UsageEntry.swift ClaudeMonitor/Pricing.swift ClaudeMonitor/LogParser.swift ClaudeMonitor/UsageStats.swift ClaudeMonitor/UsageStore.swift
```

- [ ] **Step 3: Verify it still builds**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: remove unused local-log usage pipeline"
```

---

### Task 8: Manual verification

**Files:** none (verification only)

- [ ] **Step 1: Run the app**

Open `ClaudeMonitor.xcodeproj` in Xcode and press ⌘R (or launch the built `.app`). On first launch a macOS prompt appears: "ClaudeMonitor wants to use the Claude Code-credentials keychain item." Click **Always Allow**. The menu bar should show `5h NN%`; the popover shows meters for Session / Weekly / Weekly Sonnet (and Weekly Opus if non-nil).

- [ ] **Step 2: Cross-check the numbers**

In a terminal:
```bash
TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import sys,json;print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")
curl -sS https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "anthropic-version: 2023-06-01" | python3 -m json.tool
```
Confirm the `five_hour` / `seven_day` / `seven_day_sonnet` utilization values match what the popover shows (within rounding). They should be identical since both hit the same endpoint.

- [ ] **Step 3: Verify the deny/error path**

Reason through (or test) that denying the Keychain prompt, or having no Claude Code login, lands in the `.error(...)` / `.needsLogin` state showing a message rather than crashing — the `do/catch` in `QuotaStore.refresh()` maps every failure to a `QuotaState`.
