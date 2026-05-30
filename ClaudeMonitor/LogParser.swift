//
//  LogParser.swift
//  ClaudeMonitor
//

import Foundation

/// Membaca dan mem-parse log JSONL Claude Code menjadi UsageEntry.
enum LogParser {
    /// ~/.claude/projects
    static func projectsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Parse semua entri usage dari file yang dimodifikasi sejak `since`.
    /// Dijalankan di luar main thread oleh pemanggil.
    static func parseEntries(since: Date) -> [UsageEntry] {
        let dir = projectsDirectory()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]

        var entries: [UsageEntry] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mtime = values?.contentModificationDate, mtime < since { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            content.enumerateLines { line, _ in
                if let entry = parseLine(line, iso: iso, isoNoFrac: isoNoFrac) {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    private static func parseLine(
        _ line: String,
        iso: ISO8601DateFormatter,
        isoNoFrac: ISO8601DateFormatter
    ) -> UsageEntry? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return nil }

        let model = message["model"] as? String ?? "unknown"
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

        let tsString = obj["timestamp"] as? String ?? ""
        let timestamp = iso.date(from: tsString)
            ?? isoNoFrac.date(from: tsString)
            ?? Date(timeIntervalSince1970: 0)

        var dedupKey: String?
        if let mid = message["id"] as? String, let rid = obj["requestId"] as? String {
            dedupKey = "\(mid):\(rid)"
        }

        return UsageEntry(
            timestamp: timestamp,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            dedupKey: dedupKey
        )
    }
}
