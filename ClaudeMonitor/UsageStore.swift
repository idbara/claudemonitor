//
//  UsageStore.swift
//  ClaudeMonitor
//

import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published var stats: UsageStats = .empty
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    private var timer: Timer?

    init() {
        refresh()
        // Auto-refresh tiap 60 detik.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let now = Date()
        let calendar = Calendar.current
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now

        Task.detached(priority: .utility) {
            let entries = LogParser.parseEntries(since: startOfMonth)
            let stats = UsageAggregator.aggregate(entries: entries, now: now, calendar: calendar)
            await MainActor.run {
                self.stats = stats
                self.lastUpdated = Date()
                self.isRefreshing = false
            }
        }
    }
}
