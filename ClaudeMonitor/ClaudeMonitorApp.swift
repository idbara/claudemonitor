//
//  ClaudeMonitorApp.swift
//  ClaudeMonitor
//
//  Created by Bara Ramadhan on 30/05/26.
//

import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var store = QuotaStore()

    var body: some Scene {
        MenuBarExtra {
            QuotaPopover(store: store)
        } label: {
            Image(systemName: "cpu")
            Text(menuLabel)
        }
        .menuBarExtraStyle(.window)
    }

    /// Label menu bar = utilisasi window 5 jam, mis. "5h 26%".
    private var menuLabel: String {
        if let u = store.quota?.fiveHour?.utilization {
            return "5h \(Int(u.rounded()))%"
        }
        return ""
    }
}

/// Isi popover: satu meter per window kuota.
struct QuotaPopover: View {
    @ObservedObject var store: QuotaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kuota Claude")
                .font(.headline)
            Text("Langsung dari Anthropic (akun Max)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            switch store.state {
            case .loading where store.quota == nil:
                Text("Memuat…").foregroundColor(.secondary)
            case .needsLogin:
                Text("Sesi kedaluwarsa — login ulang di Claude Code")
                    .foregroundColor(.secondary)
            case .error(let msg):
                Text(msg).foregroundColor(.secondary)
            default:
                if let q = store.quota {
                    meter("Session (5 jam)", q.fiveHour)
                    meter("Weekly (7 hari)", q.sevenDay)
                    meter("Weekly Sonnet (7 hari)", q.sevenDaySonnet)
                    meter("Weekly Opus (7 hari)", q.sevenDayOpus)
                } else {
                    Text("Memuat…").foregroundColor(.secondary)
                }
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
        .frame(width: 280)
        .onAppear { store.refresh() }
    }

    /// Tampilkan meter hanya bila window tidak nil.
    @ViewBuilder
    private func meter(_ title: String, _ window: QuotaWindow?) -> some View {
        if let w = window {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.subheadline)
                    Spacer()
                    Text("\(Int(w.utilization.rounded()))%")
                        .font(.subheadline).bold()
                }
                ProgressView(value: min(max(w.utilization, 0), 100), total: 100)
                if let reset = w.resetsAt {
                    Text("reset dalam \(Self.countdown(to: reset))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// "Xj Ym" sampai `date` (atau "<1m" / "sekarang").
    static func countdown(to date: Date) -> String {
        let secs = Int(date.timeIntervalSinceNow)
        if secs <= 0 { return "sekarang" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)j \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
