//
//  Checks/main.swift
//  Program cek logika murni (project tidak punya test target).
//  Jalankan:
//    swiftc ClaudeMonitor/AccountMath.swift ClaudeMonitor/Account.swift ClaudeMonitor/Credentials.swift ClaudeMonitor/Profile.swift ClaudeMonitor/ProfileCache.swift ClaudeMonitor/QuotaUsage.swift ClaudeMonitor/QuotaClient.swift ClaudeMonitor/AccountStore.swift Checks/main.swift -o "$TMPDIR/am-checks" && "$TMPDIR/am-checks"
//

import Foundation

var failures: [String] = []
func check(_ cond: Bool, _ name: String) {
    if !cond { failures.append(name) }
}

check(AccountMath.serviceName(forConfigDir: "/Users/bara/.claude-abati") == "Claude Code-credentials-c6b43821", "hashMatchesClaudeCode")
check(AccountMath.serviceName(forConfigDir: "/Users/bara/.claude") == "Claude Code-credentials-6ea33fa1", "hashDefaultDir")
check(AccountMath.suffix(ofService: "Claude Code-credentials") == nil, "suffixDefault")
check(AccountMath.suffix(ofService: "Claude Code-credentials-c6b43821") == "c6b43821", "suffixHex")
check(AccountMath.isClaudeService("Claude Code-credentials"), "isServiceDefault")
check(AccountMath.isClaudeService("Claude Code-credentials-c6b43821"), "isServiceSuffixed")
check(!AccountMath.isClaudeService("Claude Code-credentials-xyz"), "rejectsNonHex")
check(!AccountMath.isClaudeService("Other"), "rejectsOther")
check(AccountMath.label(forDirName: ".claude-abati") == "abati", "labelStrip")
check(AccountMath.label(forDirName: ".claude") == "claude", "labelBare")
check(AccountMath.launchCommand(dirName: nil, home: "/Users/b") == "claude", "launchDefault")
check(AccountMath.launchCommand(dirName: ".claude-abati", home: "/Users/b") == "CLAUDE_CONFIG_DIR=~/.claude-abati claude", "launchSafe")
check(AccountMath.launchCommand(dirName: ".claude my", home: "/Users/b") == "CLAUDE_CONFIG_DIR='/Users/b/.claude my' claude", "launchCommandQuotesUnsafeNames")
check(AccountMath.launchCommand(dirName: ".claude'x", home: "/Users/b") == "CLAUDE_CONFIG_DIR='/Users/b/.claude'\\''x' claude", "launchCommandEscapesQuote")

let t0 = Date(timeIntervalSince1970: 1000), t1 = Date(timeIntervalSince1970: 2000)
check(AccountMath.dedupe([
    .init(id: "a", uuid: "u", expiresAt: t0),
    .init(id: "b", uuid: "u", expiresAt: t1),
    .init(id: "c", uuid: nil, expiresAt: nil),
]) == ["b", "c"], "dedupeKeepsLatestExpiry")

check(AccountMath.recommend([.init(id: "x", fiveHour: 78, sevenDay: 65), .init(id: "y", fiveHour: 12, sevenDay: 40)]) == "y", "recommendMostHeadroom")
check(AccountMath.recommend([.init(id: "x", fiveHour: 10, sevenDay: 90), .init(id: "y", fiveHour: 50, sevenDay: 50)]) == "y", "recommendUsesWorstWindow")
check(AccountMath.recommend([.init(id: "x", fiveHour: 100, sevenDay: 20), .init(id: "y", fiveHour: 30, sevenDay: 100)]) == nil, "noRecommendationWhenAllFull")
check(AccountMath.recommend([.init(id: "x", fiveHour: 10, sevenDay: 10)]) == nil, "noStarForSingleAccount")

check(AccountMath.menuLabel(accountCount: 1, recommendedLabel: nil, fiveHour: 29.4) == "5h 29%", "menuLabelSingleAccount")
check(AccountMath.menuLabel(accountCount: 2, recommendedLabel: "abati", fiveHour: 12.0) == "★abati 12%", "menuLabelStar")
check(AccountMath.menuLabel(accountCount: 2, recommendedLabel: nil, fiveHour: nil) == "", "menuLabelNoData")

// AccountDiscovery.build: cocokkan item Keychain ke folder, buang yatim.
let built = AccountDiscovery.build(
    services: ["Claude Code-credentials-c6b43821", "Claude Code-credentials", "Claude Code-credentials-deadbeef"],
    dirNames: [".claude", ".claude-abati", ".claude-mem"],
    home: "/Users/bara")
check(built.map(\.label) == ["default", "abati"], "discoveryDropsOrphansDefaultFirst")
check(built.first?.command == "claude", "discoveryDefaultCommand")
check(built.last?.command == "CLAUDE_CONFIG_DIR=~/.claude-abati claude", "discoverySuffixedCommand")
check(built.last?.id == "Claude Code-credentials-c6b43821", "discoveryIdIsService")

// Profile: uuid dari respons API; ProfileCache simpan per service.
let profileJSON = #"{"account":{"uuid":"u-1","email":"a@b.c","full_name":"Bara","has_claude_max":true}}"#
let profile = try? JSONDecoder().decode(Profile.self, from: Data(profileJSON.utf8))
check(profile?.uuid == "u-1", "profileDecodesUUID")
let suite = UserDefaults(suiteName: "ClaudeMonitorChecks")!
suite.removePersistentDomain(forName: "ClaudeMonitorChecks")
if let profile {
    ProfileCache.set(CachedProfile(profile), for: "svc-a", defaults: suite)
}
check(ProfileCache.get("svc-a", defaults: suite) == CachedProfile(uuid: "u-1", fullName: "Bara", email: "a@b.c", hasClaudeMax: true), "profileCacheRoundTrip")
check(ProfileCache.get("svc-b", defaults: suite) == nil, "profileCacheMissing")
suite.removePersistentDomain(forName: "ClaudeMonitorChecks")

// AccountStore.arrange: gabung duplikat, ★ hanya dari akun .ok, ★ di atas.
func usage(_ five: Double, _ seven: Double) -> QuotaUsage {
    let json = #"{"five_hour":{"utilization":\#(five),"resets_at":null},"seven_day":{"utilization":\#(seven),"resets_at":null}}"#
    return try! JSONDecoder().decode(QuotaUsage.self, from: Data(json.utf8))
}
func status(_ service: String, _ label: String, uuid: String?, exp: Double?, state: AccountState, quota: QuotaUsage?) -> AccountStatus {
    AccountStatus(account: Account(id: service, service: service, label: label, command: "claude"),
                  profile: uuid.map { CachedProfile(uuid: $0, fullName: nil, email: nil, hasClaudeMax: false) },
                  quota: quota, state: state, expiresAt: exp.map { Date(timeIntervalSince1970: $0) })
}
let arranged = AccountStore.arrange([
    status(AccountMath.defaultService, "default", uuid: "u1", exp: 2000, state: .ok, quota: usage(78, 65)),
    status("svc-abati", "abati", uuid: "u2", exp: 2000, state: .ok, quota: usage(12, 40)),
    status("svc-old", "old", uuid: "u2", exp: 1000, state: .expired, quota: nil),
    status("svc-zed", "zed", uuid: "u3", exp: 500, state: .expired, quota: usage(0, 0)),
])
check(arranged.visible.map(\.id) == ["svc-abati", AccountMath.defaultService, "svc-zed"], "arrangeDedupesAndSortsStarFirst")
check(arranged.recommendedID == "svc-abati", "arrangeRecommendsOnlyOkAccounts")
check(AccountStore.menuLabel(visible: arranged.visible, recommendedID: arranged.recommendedID) == "★abati 12%", "storeMenuLabelStar")
let single = AccountStore.arrange([status(AccountMath.defaultService, "default", uuid: "u1", exp: 2000, state: .ok, quota: usage(29.4, 10))])
check(single.recommendedID == nil, "arrangeSingleNoStar")
check(AccountStore.menuLabel(visible: single.visible, recommendedID: single.recommendedID) == "5h 29%", "storeMenuLabelSingle")
let full = AccountStore.arrange([
    status(AccountMath.defaultService, "default", uuid: "u1", exp: 2000, state: .ok, quota: usage(100, 50)),
    status("svc-abati", "abati", uuid: "u2", exp: 2000, state: .ok, quota: usage(60, 100)),
])
check(full.recommendedID == nil, "arrangeAllFullNoStar")
check(AccountStore.menuLabel(visible: full.visible, recommendedID: full.recommendedID) == "5h 100%", "storeMenuLabelFallsBackToDefault")

if failures.isEmpty {
    print("ALL CHECKS PASSED")
} else {
    print("FAILED: \(failures.joined(separator: ", "))")
    exit(1)
}
