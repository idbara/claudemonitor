//
//  NotificationPlanner.swift
//  ClaudeMonitor
//
//  Logika murni notifikasi limit: dari data akun + catatan yang sudah dikirim,
//  tentukan notifikasi yang dikirim sekarang dan yang dijadwalkan ke macOS.
//  Dicek lewat Checks/main.swift.
//

import Foundation

nonisolated struct PlannedNote: Equatable {
    let id: String
    let title: String
    let body: String
    /// nil = kirim sekarang.
    let fireDate: Date?
}

nonisolated enum NotificationPlanner {
    static let thresholds: [Double] = [80, 95]
    static let fullAt: Double = 80                       // usableSoon & didReset
    static let minHeadroom: Double = 20                  // expiring
    static let usableLead: TimeInterval = 15 * 60
    static let expiringLead: TimeInterval = 30 * 60
    static let didResetGrace: TimeInterval = 15 * 60

    private enum Window: String {
        case fiveHour, sevenDay
        var label: String { self == .fiveHour ? "5 jam" : "mingguan" }
    }

    static func plan(_ accounts: [AccountStatus], now: Date, ledger: Set<String>)
        -> (immediate: [PlannedNote], scheduled: [PlannedNote], newKeys: Set<String>) {
        var immediate: [PlannedNote] = [], scheduled: [PlannedNote] = [], keys = Set<String>()

        for s in accounts {
            guard let q = s.quota else { continue }
            let seven = q.sevenDay?.utilization
            let windows: [(Window, QuotaWindow?, Double)] = [
                // Sisa 5 jam tetap dibatasi limit mingguan.
                (.fiveHour, q.fiveHour, 100 - max(q.fiveHour?.utilization ?? 0, seven ?? 0)),
                (.sevenDay, q.sevenDay, 100 - (seven ?? 0)),
            ]
            for (window, w, headroom) in windows {
                guard let w else { continue }
                let util = w.utilization
                let reset = w.resetsAt
                let epoch = reset.map { Int($0.timeIntervalSince1970) } ?? 0
                let base = "cm.\(s.account.service).\(window.rawValue)"
                let title = "\(s.account.label) · \(window.label)"
                let windowLive = reset.map { $0 > now } ?? true

                // Hampir habis: hanya ambang tertinggi yang belum pernah dikirim.
                if windowLive {
                    let crossed = thresholds.filter { util >= $0 }
                    let crossedKeys = crossed.map { "\(base).nearLimit.\(Int($0)).\(epoch)" }
                    if let top = crossedKeys.last, !ledger.contains(top) {
                        var body = "Sudah \(Int(util.rounded()))% terpakai"
                        if let reset { body += " — reset \(countdown(reset.timeIntervalSince(now))) lagi" }
                        immediate.append(PlannedNote(id: top, title: title, body: body, fireDate: nil))
                    }
                    keys.formUnion(crossedKeys)
                }

                guard let reset else { continue }
                func timed(_ kind: String, fire: Date, deadline: Date, body: (Date) -> String) {
                    let key = "\(base).\(kind).\(epoch)"
                    if fire > now {
                        scheduled.append(PlannedNote(id: key, title: title, body: body(fire), fireDate: fire))
                        keys.insert(key)
                    } else if now < deadline && !ledger.contains(key) {
                        immediate.append(PlannedNote(id: key, title: title, body: body(now), fireDate: nil))
                        keys.insert(key)
                    }
                }
                func minutesLeft(_ at: Date) -> Int { max(1, Int((reset.timeIntervalSince(at) / 60).rounded(.up))) }

                if util >= fullAt {
                    timed("usableSoon", fire: reset.addingTimeInterval(-usableLead), deadline: reset) {
                        "Hampir penuh (\(Int(util.rounded()))%) — reset \(minutesLeft($0)) menit lagi"
                    }
                    timed("didReset", fire: reset, deadline: reset.addingTimeInterval(didResetGrace)) { _ in
                        "Limit \(window.label) sudah reset — kembali 100%"
                    }
                }
                if headroom >= minHeadroom {
                    timed("expiring", fire: reset.addingTimeInterval(-expiringLead), deadline: reset) {
                        "Sisa \(Int(headroom.rounded()))% hangus dalam \(minutesLeft($0)) menit — pakai sekarang"
                    }
                }
            }
        }
        return (immediate, scheduled, keys)
    }

    /// "Xj Ym" / "Ym" / "<1m".
    static func countdown(_ seconds: TimeInterval) -> String {
        let secs = Int(seconds)
        let h = secs / 3600, m = (secs % 3600) / 60
        if h > 0 { return "\(h)j \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
