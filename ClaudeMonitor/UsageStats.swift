//
//  UsageStats.swift
//  ClaudeMonitor
//

import Foundation

struct ModelUsage: Identifiable {
    let model: String
    let tokens: Int
    let cost: Double
    var id: String { model }
}

struct UsageStats {
    var todayTokens: Int = 0
    var todayCost: Double = 0
    var monthTokens: Int = 0
    var monthCost: Double = 0
    var blockTokens: Int = 0
    var blockCost: Double = 0
    var blockStart: Date?
    var perModel: [ModelUsage] = []

    var isEmpty: Bool { monthTokens == 0 }

    static let empty = UsageStats()
}

enum UsageAggregator {
    /// Bangun UsageStats dari entri. `now`/`calendar` di-inject agar deterministik.
    static func aggregate(entries: [UsageEntry], now: Date, calendar: Calendar = .current) -> UsageStats {
        // Dedup berdasarkan dedupKey; entri tanpa key selalu dihitung.
        var seen = Set<String>()
        let deduped = entries.filter { entry in
            guard let key = entry.dedupKey else { return true }
            return seen.insert(key).inserted
        }

        let startOfDay = calendar.startOfDay(for: now)
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? startOfDay

        var stats = UsageStats()
        var perModelTokens: [String: Int] = [:]
        var perModelCost: [String: Double] = [:]

        for entry in deduped {
            let cost = Pricing.cost(for: entry)
            let tokens = entry.totalTokens

            if entry.timestamp >= startOfMonth {
                stats.monthTokens += tokens
                stats.monthCost += cost
            }
            if entry.timestamp >= startOfDay {
                stats.todayTokens += tokens
                stats.todayCost += cost
                perModelTokens[entry.model, default: 0] += tokens
                perModelCost[entry.model, default: 0] += cost
            }
        }

        stats.perModel = perModelTokens.map { model, tokens in
            ModelUsage(model: model, tokens: tokens, cost: perModelCost[model] ?? 0)
        }.sorted { $0.cost > $1.cost }

        if let block = activeBlock(deduped: deduped, now: now, calendar: calendar) {
            stats.blockStart = block.start
            for entry in deduped where entry.timestamp >= block.start && entry.timestamp < block.end {
                stats.blockTokens += entry.totalTokens
                stats.blockCost += Pricing.cost(for: entry)
            }
        }

        return stats
    }

    /// Block 5-jam ala ccusage: start = aktivitas pertama dibulatkan ke bawah ke
    /// jam bulat; block 5 jam; block baru bila entri keluar window atau ada gap >5 jam.
    /// Mengembalikan block yang memuat `now`, atau nil bila tidak ada yang aktif.
    private static func activeBlock(
        deduped: [UsageEntry],
        now: Date,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let sorted = deduped.map(\.timestamp).sorted()
        guard let first = sorted.first else { return nil }

        let blockDuration: TimeInterval = 5 * 60 * 60
        var blockStart = floorToHour(first, calendar: calendar)
        var lastTimestamp = first

        for ts in sorted {
            let sinceStart = ts.timeIntervalSince(blockStart)
            let sinceLast = ts.timeIntervalSince(lastTimestamp)
            if sinceStart >= blockDuration || sinceLast >= blockDuration {
                blockStart = floorToHour(ts, calendar: calendar)
            }
            lastTimestamp = ts
        }

        let blockEnd = blockStart.addingTimeInterval(blockDuration)
        if now >= blockStart && now < blockEnd {
            return (blockStart, blockEnd)
        }
        return nil
    }

    private static func floorToHour(_ date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: comps) ?? date
    }
}
