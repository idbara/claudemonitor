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
    @Published var profile: Profile?
    @Published var state: QuotaState = .loading
    @Published var lastUpdated: Date?

    // Endpoint oauth/usage dibatasi ketat (429 retry-after ~4 menit), jadi
    // polling jarang. Data utilisasi berubah lambat — 5 menit sudah cukup.
    private static let refreshInterval: TimeInterval = 300

    private var timer: Timer?
    private var isRefreshing = false
    private var retryTask: Task<Void, Never>?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    /// Refresh hanya bila data sudah usang — dipakai saat popover dibuka agar
    /// membuka-tutup berulang tidak menghabiskan jatah rate-limit.
    func refreshIfStale(maxAge: TimeInterval = 120) {
        if let last = lastUpdated, Date().timeIntervalSince(last) < maxAge { return }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }   // jangan tumpuk request
        isRefreshing = true
        if quota == nil { state = .loading }  // jangan kosongkan data yang sudah ada

        Task { [weak self] in
            defer { self?.isRefreshing = false }
            do {
                let creds = try Credentials.load()
                // Profil jarang berubah — ambil sekali saja (best-effort).
                if self?.profile == nil {
                    self?.profile = try? await QuotaClient.fetchProfile(accessToken: creds.accessToken)
                }
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
            } catch QuotaClientError.rateLimited(let retryAfter) {
                // Pertahankan data lama bila ada; kalau belum ada, jadwalkan retry.
                if self?.quota == nil {
                    self?.state = .error("Dibatasi sementara oleh Anthropic — mencoba lagi…")
                    self?.scheduleRetry(after: retryAfter ?? 60)
                }
            } catch QuotaClientError.network {
                if self?.quota == nil { self?.state = .error("Tidak bisa terhubung ke Anthropic") }
            } catch {
                if self?.quota == nil { self?.state = .error("Gagal mengambil kuota") }
            }
        }
    }

    /// Satu kali retry setelah `seconds` (dibatasi 5–300 dtk), hormati Retry-After.
    private func scheduleRetry(after seconds: TimeInterval) {
        retryTask?.cancel()
        let delay = min(max(seconds, 5), 300)
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled { self?.refresh() }
        }
    }
}
