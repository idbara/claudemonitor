//
//  LoginItem.swift
//  ClaudeMonitor
//

import Foundation
import Combine
import ServiceManagement

/// Toggle "Buka saat login" lewat SMAppService.mainApp.
/// Catatan: yang didaftarkan adalah lokasi app saat ini — install ke /Applications dulu.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false

    init() { reload() }

    func reload() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            print("[ClaudeMonitor] gagal mengubah login item: \(error)")
        }
        reload()
    }
}
