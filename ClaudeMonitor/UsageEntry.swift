//
//  UsageEntry.swift
//  ClaudeMonitor
//

import Foundation

/// Satu baris usage dari log Claude Code (~/.claude/projects/**/*.jsonl).
struct UsageEntry {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    /// "<message.id>:<requestId>" bila keduanya ada; dipakai untuk dedup.
    let dedupKey: String?

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}
