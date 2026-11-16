//
//  ClaudeMonitorApp.swift
//  ClaudeMonitor
//
//  Created by Bara Ramadhan on 30/05/26.
//

import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        MenuBarExtra {
            QuotaPopover(store: store)
        } label: {
            // Monokrom (template) ikut warna menu bar.
            // Ukuran ikon diatur lewat padding di dalam SVG (frame diabaikan menu bar).
            Image("ClaudeLogo")
                .renderingMode(.template)
            Text(menuLabel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuLabel: String { store.menuLabel }
}

/// Isi popover: satu baris per akun Claude Code, ★ = disarankan dipakai berikutnya.
struct QuotaPopover: View {
    @ObservedObject var store: AccountStore
    @StateObject private var loginItem = LoginItem()
    @State private var expanded: Set<String> = []
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.accounts.isEmpty {
                Text(store.hasDiscovered ? "Tidak menemukan kredensial Claude Code" : "Memuat…")
                    .foregroundColor(.secondary)
            }
            ForEach(store.accounts) { s in
                accountRow(s)
                if s.id != store.accounts.last?.id { Divider() }
            }

            Divider()
            if let updated = store.lastUpdated {
                Text("Diperbarui \(updated, format: .dateTime.hour().minute().second())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Toggle("Buka saat login", isOn: Binding(
                get: { loginItem.isEnabled || loginItem.needsApproval },
                set: { loginItem.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            if loginItem.needsApproval {
                Text("Setujui di Pengaturan Sistem › Item Login")
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
        .frame(width: 300)
        .onAppear {
            store.refreshIfStale()
            loginItem.reload()
        }
    }

    /// Satu akun: klik baris = salin perintah; chevron = buka meter lengkap.
    @ViewBuilder
    private func accountRow(_ s: AccountStatus) -> some View {
        let isRec = s.id == store.recommendedID
        let isOpen = expanded.contains(s.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Button { copy(s) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(isRec ? "★" : " ").foregroundColor(.accentColor)
                            Text(s.account.label).bold()
                            if s.profile?.hasClaudeMax == true {
                                Text("Max")
                                    .font(.caption2).bold()
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        if let q = s.quota {
                            HStack(spacing: 8) {
                                compact("5h", q.fiveHour)
                                compact("7d", q.sevenDay)
                            }
                            .opacity(s.state == .ok ? 1 : 0.5)
                        }
                        Text(caption(s))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(s.account.command)

                Button {
                    if isOpen { expanded.remove(s.id) } else { expanded.insert(s.id) }
                } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .disabled(s.quota == nil)
            }
            if isOpen, let q = s.quota {
                meter("Session (5 jam)", q.fiveHour)
                meter("Weekly (7 hari)", q.sevenDay)
                meter("Weekly Sonnet (7 hari)", q.sevenDaySonnet)
                meter("Weekly Opus (7 hari)", q.sevenDayOpus)
            }
        }
    }

    /// Meter ringkas "5h ▓░ 12%".
    @ViewBuilder
    private func compact(_ title: String, _ window: QuotaWindow?) -> some View {
        if let w = window {
            HStack(spacing: 4) {
                Text(title).font(.caption).foregroundColor(.secondary)
                ProgressView(value: min(max(w.utilization, 0), 100), total: 100)
                    .frame(width: 60)
                Text("\(Int(w.utilization.rounded()))%").font(.caption).bold()
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }

    /// Baris keterangan: "Disalin ✓", peringatan token, atau nama + reset 5 jam.
    private func caption(_ s: AccountStatus) -> String {
        if copiedID == s.id { return "Disalin ✓  \(s.account.command)" }
        switch s.state {
        case .expired, .needsLogin:
            return "⚠ token kedaluwarsa — jalankan claude di akun ini"
        case .error(let msg) where s.quota == nil:
            return msg
        case .loading where s.quota == nil:
            return "Memuat…"
        default:
            var parts: [String] = []
            if let name = s.profile?.fullName ?? s.profile?.email { parts.append(name) }
            if let reset = s.quota?.fiveHour?.resetsAt { parts.append("reset dalam \(Self.countdown(to: reset))") }
            return parts.joined(separator: " · ")
        }
    }

    /// Salin perintah peluncuran akun ke clipboard, tampilkan "Disalin ✓" sebentar.
    private func copy(_ s: AccountStatus) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s.account.command, forType: .string)
        copiedID = s.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedID == s.id { copiedID = nil }
        }
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
