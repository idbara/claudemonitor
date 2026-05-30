//
//  Pricing.swift
//  ClaudeMonitor
//

import Foundation

// PRICING: update when Anthropic rates change. USD per 1.000.000 token.
enum Pricing {
    struct Rates {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double
    }

    /// Cocokkan berdasarkan substring nama model supaya id bertanggal tetap kena.
    static func rates(for model: String) -> Rates {
        let m = model.lowercased()
        if m.contains("opus") {
            // Opus 4.6 / 4.8. (Opus 4 / 4.1 lama lebih mahal: 15/75/18.75/1.50.)
            // Diverifikasi terhadap ccusage: cocok untuk opus-4-6 & opus-4-8.
            return Rates(input: 5.0, output: 25.0, cacheWrite: 6.25, cacheRead: 0.50)
        }
        if m.contains("haiku") {
            return Rates(input: 1.0, output: 5.0, cacheWrite: 1.25, cacheRead: 0.10)
        }
        if m.contains("sonnet") {
            return Rates(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
        }
        // fallback (kelas sonnet)
        return Rates(input: 3.0, output: 15.0, cacheWrite: 3.75, cacheRead: 0.30)
    }

    /// Equivalent cost (USD) untuk satu entri.
    static func cost(for entry: UsageEntry) -> Double {
        let r = rates(for: entry.model)
        return (Double(entry.inputTokens) * r.input
              + Double(entry.outputTokens) * r.output
              + Double(entry.cacheCreationTokens) * r.cacheWrite
              + Double(entry.cacheReadTokens) * r.cacheRead) / 1_000_000.0
    }
}
