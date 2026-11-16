//
//  Checks/main.swift
//  Program cek logika murni (project tidak punya test target).
//  Jalankan:
//    swiftc ClaudeMonitor/AccountMath.swift Checks/main.swift -o "$TMPDIR/am-checks" && "$TMPDIR/am-checks"
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

if failures.isEmpty {
    print("ALL CHECKS PASSED")
} else {
    print("FAILED: \(failures.joined(separator: ", "))")
    exit(1)
}
