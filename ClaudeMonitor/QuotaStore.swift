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
            guard let self else { return }
            Task { @MainActor in self.refresh() }
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
