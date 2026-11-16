//
//  AccountsExport.swift
//  ClaudeMonitor
//
//  Menulis ~/Library/Application Support/ClaudeMonitor/accounts.json supaya
//  `cc` bisa memilih akun berikutnya tanpa memanggil endpoint kuota sendiri.
//  Tidak berisi token maupun email.
//

import Foundation

nonisolated enum AccountsExport {
    private struct Entry: Encodable {
        let id: String
        let label: String
        let configDir: String?
        let state: String
        let fiveHour: Double?
        let sevenDay: Double?
        let fiveHourResetsAt: String?
        let headroom: Double?

        // Tulis null secara eksplisit (bukan menghilangkan key) agar bentuknya tetap.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(label, forKey: .label)
            try c.encode(configDir, forKey: .configDir)
            try c.encode(state, forKey: .state)
            try c.encode(fiveHour, forKey: .fiveHour)
            try c.encode(sevenDay, forKey: .sevenDay)
            try c.encode(fiveHourResetsAt, forKey: .fiveHourResetsAt)
            try c.encode(headroom, forKey: .headroom)
        }
        private enum CodingKeys: String, CodingKey {
            case id, label, configDir, state, fiveHour, sevenDay, fiveHourResetsAt, headroom
        }
    }

    private struct Root: Encodable {
        let updatedAt: String
        let recommended: String?
        let accounts: [Entry]

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(updatedAt, forKey: .updatedAt)
            try c.encode(recommended, forKey: .recommended)
            try c.encode(accounts, forKey: .accounts)
        }
        private enum CodingKeys: String, CodingKey { case updatedAt, recommended, accounts }
    }

    private static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    private static func stateName(_ s: AccountState) -> String {
        switch s {
        case .loading: return "loading"
        case .ok: return "ok"
        case .expired: return "expired"
        case .needsLogin: return "needsLogin"
        case .error: return "error"
        }
    }

    static func json(visible: [AccountStatus], recommendedID: String?, now: Date) -> Data {
        let entries = visible.map { s -> Entry in
            let five = s.quota?.fiveHour?.utilization
            let seven = s.quota?.sevenDay?.utilization
            return Entry(id: s.id, label: s.account.label, configDir: s.account.configDir,
                         state: stateName(s.state), fiveHour: five, sevenDay: seven,
                         fiveHourResetsAt: s.quota?.fiveHour?.resetsAt.map(iso),
                         headroom: s.quota == nil ? nil : 100 - max(five ?? 0, seven ?? 0))
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(Root(updatedAt: iso(now), recommended: recommendedID, accounts: entries))) ?? Data()
    }

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeMonitor/accounts.json")
    }

    /// Tulis atomik; kegagalan diabaikan (ekspor hanya pelengkap).
    static func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
