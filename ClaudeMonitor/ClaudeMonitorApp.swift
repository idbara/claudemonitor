//
//  ClaudeMonitorApp.swift
//  ClaudeMonitor
//
//  Created by Bara Ramadhan on 30/05/26.
//

import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        // Label menu bar = equivalent cost hari ini.
        MenuBarExtra {
            UsagePopover(store: store)
        } label: {
            Image(systemName: "cpu")
            Text("≈ $\(store.stats.todayCost, specifier: "%.2f")")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Isi popover menu bar.
struct UsagePopover: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Code Usage")
                .font(.headline)
            Text("≈ equivalent cost (subscription — bukan tagihan nyata)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            if store.stats.isEmpty {
                Text("Belum ada data usage")
                    .foregroundColor(.secondary)
            } else {
                amountRow("Hari ini", tokens: store.stats.todayTokens, cost: store.stats.todayCost)

                if let start = store.stats.blockStart {
                    VStack(alignment: .leading, spacing: 2) {
                        amountRow("Sesi 5-jam", tokens: store.stats.blockTokens, cost: store.stats.blockCost)
                        Text("mulai \(start, format: .dateTime.hour().minute())")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Text("Sesi 5-jam")
                        Spacer()
                        Text("tidak aktif").foregroundColor(.secondary)
                    }
                }

                Divider()
                Text("Per model (hari ini)")
                    .font(.subheadline).bold()
                ForEach(store.stats.perModel) { m in
                    HStack {
                        Text(shortModel(m.model))
                        Spacer()
                        Text("≈ $\(m.cost, specifier: "%.2f")")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }

                Divider()
                amountRow("Bulan ini", tokens: store.stats.monthTokens, cost: store.stats.monthCost)
            }

            Divider()
            if let updated = store.lastUpdated {
                Text("Diperbarui \(updated, format: .dateTime.hour().minute().second())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("Refresh") { store.refresh() }
                    .keyboardShortcut("r")
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 260)
        .onAppear { store.refresh() }
    }

    @ViewBuilder
    private func amountRow(_ title: String, tokens: Int, cost: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            VStack(alignment: .trailing) {
                Text("≈ $\(cost, specifier: "%.2f")").bold()
                Text("\(tokens.formatted()) tok")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func shortModel(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return model
    }
}
