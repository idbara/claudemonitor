//
//  AccountStore.swift
//  ClaudeMonitor
//

import Foundation
import Combine

nonisolated enum AccountState: Equatable {
    case loading
    case ok
    case expired      // token lewat expiresAt — tidak memanggil API
    case needsLogin   // 401/403
    case error(String)
}

nonisolated struct AccountStatus: Identifiable {
    let account: Account
    var profile: CachedProfile?
    var quota: QuotaUsage?
    var state: AccountState
    var expiresAt: Date?
    var id: String { account.id }
}

@MainActor
final class AccountStore: ObservableObject {
    /// Akun yang ditampilkan (sudah digabung & diurutkan: ★ dulu).
    @Published private(set) var accounts: [AccountStatus] = []
    @Published private(set) var recommendedID: String?
    @Published private(set) var lastUpdated: Date?
    /// true setelah discovery pertama selesai (bedakan "memuat" vs "tidak ada akun").
    @Published private(set) var hasDiscovered = false

    // Endpoint oauth/usage dibatasi ketat (429 retry-after ~4 menit), jadi
    // polling jarang. Data utilisasi berubah lambat — 5 menit sudah cukup.
    private static let refreshInterval: TimeInterval = 300

    /// Semua akun hasil discovery (sebelum digabung), per id/service.
    private var all: [String: AccountStatus] = [:]
    private var order: [String] = []
    /// Profil diambil ulang sekali per sesi app per akun (cache hanya nilai awal).
    private var profileFetched: Set<String> = []
    private var timer: Timer?
    private var isRefreshing = false
    private var retryTasks: [String: Task<Void, Never>] = [:]

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    var menuLabel: String { Self.menuLabel(visible: accounts, recommendedID: recommendedID) }

    /// Refresh hanya bila data sudah usang — dipakai saat popover dibuka agar
    /// membuka-tutup berulang tidak menghabiskan jatah rate-limit.
    func refreshIfStale(maxAge: TimeInterval = 120) {
        if let last = lastUpdated, Date().timeIntervalSince(last) < maxAge { return }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }   // jangan tumpuk request
        isRefreshing = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRefreshing = false }

            // Discovery ulang tiap siklus (murah: hanya atribut Keychain).
            let found = AccountDiscovery.discover()
            var next: [String: AccountStatus] = [:]
            for a in found {
                if var old = all[a.id] {
                    old = AccountStatus(account: a, profile: old.profile, quota: old.quota,
                                        state: old.state, expiresAt: old.expiresAt)
                    next[a.id] = old
                } else {
                    next[a.id] = AccountStatus(account: a, profile: ProfileCache.get(a.service),
                                               quota: nil, state: .loading, expiresAt: nil)
                }
            }
            all = next
            order = found.map(\.id)
            hasDiscovered = true
            publish()

            // Berurutan, bukan paralel — satu akun gagal tidak menghentikan yang lain.
            var anyOK = false
            for id in order {
                await refreshOne(id)
                if all[id]?.state == .ok { anyOK = true }
                publish()
            }
            if anyOK { lastUpdated = Date() }
        }
    }

    private func refreshOne(_ id: String) async {
        guard var s = all[id] else { return }
        let service = s.account.service
        do {
            let creds = try Credentials.load(service: service)
            s.expiresAt = creds.expiresAt
            if let exp = creds.expiresAt, exp < Date() {
                s.state = .expired
                all[id] = s
                return
            }
            if !profileFetched.contains(id),
               let p = try? await QuotaClient.fetchProfile(accessToken: creds.accessToken) {
                let cached = CachedProfile(p)
                ProfileCache.set(cached, for: service)
                s.profile = cached
                profileFetched.insert(id)
            }
            s.quota = try await QuotaClient.fetch(accessToken: creds.accessToken)
            s.state = .ok
        } catch CredentialsError.notFound {
            s.state = .error("Tidak menemukan kredensial Claude Code")
        } catch CredentialsError.unreadable {
            s.state = .error("Tidak bisa baca kredensial Claude Code")
        } catch QuotaClientError.unauthorized {
            s.state = .needsLogin
        } catch QuotaClientError.rateLimited(let retryAfter) {
            // Pertahankan data lama bila ada; kalau belum ada, jadwalkan retry akun ini saja.
            if s.quota == nil {
                s.state = .error("Dibatasi sementara oleh Anthropic — mencoba lagi…")
                scheduleRetry(id, after: retryAfter ?? 60)
            }
        } catch QuotaClientError.network {
            if s.quota == nil { s.state = .error("Tidak bisa terhubung ke Anthropic") }
        } catch {
            if s.quota == nil { s.state = .error("Gagal mengambil kuota") }
        }
        // Discovery bisa saja membuang akun ini selama await.
        if all[id] != nil { all[id] = s }
    }

    /// Satu kali retry untuk satu akun setelah `seconds` (5–300 dtk), hormati Retry-After.
    private func scheduleRetry(_ id: String, after seconds: TimeInterval) {
        retryTasks[id]?.cancel()
        let delay = min(max(seconds, 5), 300)
        retryTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.isRefreshing else { return }
            await self.refreshOne(id)
            self.publish()
        }
    }

    private func publish() {
        let result = Self.arrange(order.compactMap { all[$0] })
        accounts = result.visible
        recommendedID = result.recommendedID
    }

    /// Gabung duplikat (uuid sama), pilih ★ dari akun yang datanya segar, urutkan ★ → default → label.
    nonisolated static func arrange(_ statuses: [AccountStatus]) -> (visible: [AccountStatus], recommendedID: String?) {
        let keep = AccountMath.dedupe(statuses.map {
            AccountMath.DedupItem(id: $0.id, uuid: $0.profile?.uuid, expiresAt: $0.expiresAt)
        })
        let visible = statuses.filter { keep.contains($0.id) }
        let snaps = visible.compactMap { s -> AccountMath.UsageSnapshot? in
            guard s.state == .ok, let q = s.quota else { return nil }
            return AccountMath.UsageSnapshot(id: s.id, fiveHour: q.fiveHour?.utilization,
                                             sevenDay: q.sevenDay?.utilization)
        }
        let rec = AccountMath.recommend(snaps)
        let sorted = visible.sorted { a, b in
            if (a.id == rec) != (b.id == rec) { return a.id == rec }
            let ad = a.account.service == AccountMath.defaultService
            let bd = b.account.service == AccountMath.defaultService
            if ad != bd { return ad }
            return a.account.label < b.account.label
        }
        return (sorted, rec)
    }

    /// Label menu bar: akun ★, kalau tidak ada → akun default, lalu akun pertama yang punya data.
    nonisolated static func menuLabel(visible: [AccountStatus], recommendedID: String?) -> String {
        let rec = visible.first { $0.id == recommendedID }
        let target = rec
            ?? visible.first { $0.account.service == AccountMath.defaultService && $0.quota != nil }
            ?? visible.first { $0.quota != nil }
        return AccountMath.menuLabel(accountCount: visible.count,
                                     recommendedLabel: rec?.account.label,
                                     fiveHour: target?.quota?.fiveHour?.utilization)
    }
}
