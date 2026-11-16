//
//  AccountMath.swift
//  ClaudeMonitor
//
//  Logika murni multi-akun (tanpa Keychain/jaringan) supaya bisa dicek
//  terpisah lewat `Checks/main.swift`.
//

import Foundation
import CryptoKit

nonisolated enum AccountMath {
    /// Item Keychain Claude Code untuk config dir default (~/.claude).
    static let defaultService = "Claude Code-credentials"

    /// Claude Code dengan CLAUDE_CONFIG_DIR menyimpan token di
    /// "Claude Code-credentials-<8 hex pertama sha256(path absolut)>".
    static func serviceName(forConfigDir absolutePath: String) -> String {
        let digest = SHA256.hash(data: Data(absolutePath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(defaultService)-\(hex.prefix(8))"
    }

    /// nil untuk item default; "c6b43821" untuk item bersufiks.
    static func suffix(ofService service: String) -> String? {
        let prefix = defaultService + "-"
        guard service.hasPrefix(prefix) else { return nil }
        return String(service.dropFirst(prefix.count))
    }

    /// Tepat item default, atau default + "-" + 8 hex.
    static func isClaudeService(_ service: String) -> Bool {
        if service == defaultService { return true }
        guard let s = suffix(ofService: service) else { return false }
        return s.count == 8 && s.allSatisfy { $0.isHexDigit }
    }

    /// ".claude-abati" → "abati", ".claude" → "claude".
    static func label(forDirName name: String) -> String {
        let stripped: Substring
        if name.hasPrefix(".claude-") {
            stripped = name.dropFirst(".claude-".count)
        } else if name.hasPrefix(".") {
            stripped = name.dropFirst()
        } else {
            stripped = Substring(name)
        }
        return stripped.isEmpty ? name : String(stripped)
    }

    /// Perintah untuk menjalankan Claude Code di akun ini (siap ditempel ke zsh).
    static func launchCommand(dirName: String?, home: String) -> String {
        guard let dirName else { return "claude" }
        let safe = !dirName.isEmpty && dirName.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || "._-".unicodeScalars.contains($0)
        }
        if safe { return "CLAUDE_CONFIG_DIR=~/\(dirName) claude" }
        let path = "\(home)/\(dirName)".replacingOccurrences(of: "'", with: "'\\''")
        return "CLAUDE_CONFIG_DIR='\(path)' claude"
    }

    struct DedupItem {
        let id: String
        let uuid: String?
        let expiresAt: Date?
    }

    /// Item dengan uuid akun yang sama digabung: simpan token yang paling akhir kedaluwarsa.
    static func dedupe(_ items: [DedupItem]) -> Set<String> {
        var kept = Set<String>()
        var bestByUUID: [String: DedupItem] = [:]
        for item in items {
            guard let uuid = item.uuid else { kept.insert(item.id); continue }
            if let cur = bestByUUID[uuid],
               (cur.expiresAt ?? .distantPast) >= (item.expiresAt ?? .distantPast) {
                continue
            }
            bestByUUID[uuid] = item
        }
        kept.formUnion(bestByUUID.values.map(\.id))
        return kept
    }

    struct UsageSnapshot {
        let id: String
        let fiveHour: Double?
        let sevenDay: Double?
    }

    /// Akun dengan sisa limit terbanyak: 100 − max(5 jam, 7 hari).
    /// nil bila < 2 akun atau semua sudah penuh.
    static func recommend(_ snaps: [UsageSnapshot]) -> String? {
        guard snaps.count >= 2 else { return nil }
        func headroom(_ s: UsageSnapshot) -> Double { 100 - max(s.fiveHour ?? 0, s.sevenDay ?? 0) }
        let best = snaps.min { a, b in
            let ha = headroom(a), hb = headroom(b)
            if ha != hb { return ha > hb }
            let fa = a.fiveHour ?? 0, fb = b.fiveHour ?? 0
            if fa != fb { return fa < fb }
            return a.id < b.id
        }
        guard let best, headroom(best) > 0 else { return nil }
        return best.id
    }

    /// "5h 29%" untuk satu akun / tanpa rekomendasi; "★abati 12%" bila ada rekomendasi.
    static func menuLabel(accountCount: Int, recommendedLabel: String?, fiveHour: Double?) -> String {
        guard let fiveHour else { return "" }
        let pct = Int(fiveHour.rounded())
        if accountCount <= 1 || recommendedLabel == nil { return "5h \(pct)%" }
        return "★\(recommendedLabel!) \(pct)%"
    }
}
