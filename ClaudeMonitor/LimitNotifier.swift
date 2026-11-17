//
//  LimitNotifier.swift
//  ClaudeMonitor
//
//  Mengirim & menjadwalkan notifikasi limit (UserNotifications) berdasarkan
//  rencana NotificationPlanner. Dijalankan ulang setiap refresh, sehingga jadwal
//  di macOS selalu mengikuti data terbaru (paling basi 5 menit).
//

import Foundation
import Combine
import UserNotifications

/// Tampilkan banner walaupun app sedang aktif (app menu bar sering dianggap aktif).
private final class BannerPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
final class LimitNotifier: ObservableObject {
    @Published private(set) var enabled: Bool
    /// true bila izin notifikasi ditolak di macOS.
    @Published private(set) var denied = false

    private static let enabledKey = "notificationsEnabled"
    private static let ledgerKey = "notificationLedger"
    private static let ledgerMaxAge: TimeInterval = 8 * 24 * 3600
    private static let idPrefix = "cm."

    private let defaults = UserDefaults.standard
    private let presenter = BannerPresenter()
    private var authorized = false
    private var center: UNUserNotificationCenter { .current() }

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        UNUserNotificationCenter.current().delegate = presenter
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        if !on {
            Task { await removePending(keeping: []) }
        }
    }

    /// Dipanggil AccountStore setelah setiap siklus refresh.
    func update(accounts: [AccountStatus]) {
        guard enabled else { return }
        Task { await apply(accounts) }
    }

    private func apply(_ accounts: [AccountStatus]) async {
        if !authorized {
            // Hanya memunculkan prompt sekali; setelah itu mengembalikan status yang ada.
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            authorized = granted
            denied = !granted
            guard granted else { return }
        }
        let now = Date()
        let ledger = Set(defaults.stringArray(forKey: Self.ledgerKey) ?? [])
        let plan = NotificationPlanner.plan(accounts, now: now, ledger: ledger)

        for note in plan.immediate {
            try? await center.add(request(for: note))
        }
        // Ganti jadwal lama dengan rencana terbaru (identifier sama = diganti).
        await removePending(keeping: Set(plan.scheduled.map(\.id)))
        for note in plan.scheduled {
            try? await center.add(request(for: note))
        }
        let cutoff = now.timeIntervalSince1970 - Self.ledgerMaxAge
        let kept = ledger.union(plan.newKeys).filter { key in
            guard let epoch = key.split(separator: ".").last.flatMap({ Double($0) }), epoch > 0 else { return true }
            return epoch >= cutoff
        }
        defaults.set(Array(kept).sorted(), forKey: Self.ledgerKey)
    }

    private func request(for note: PlannedNote) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = note.title
        content.body = note.body
        content.sound = .default
        var trigger: UNNotificationTrigger?
        if let fire = note.fireDate {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        return UNNotificationRequest(identifier: note.id, content: content, trigger: trigger)
    }

    private func removePending(keeping keep: Set<String>) async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) && !keep.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
    }
}
