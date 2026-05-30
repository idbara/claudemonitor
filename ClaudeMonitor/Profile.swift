//
//  Profile.swift
//  ClaudeMonitor
//

import Foundation

/// Profil akun dari /api/oauth/profile (hanya field yang dipakai).
struct Profile: Decodable {
    let fullName: String?
    let email: String?
    let hasClaudeMax: Bool

    private enum RootKeys: String, CodingKey {
        case account
    }
    private enum AccountKeys: String, CodingKey {
        case fullName = "full_name"
        case email
        case hasClaudeMax = "has_claude_max"
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let account = try root.nestedContainer(keyedBy: AccountKeys.self, forKey: .account)
        fullName = try account.decodeIfPresent(String.self, forKey: .fullName)
        email = try account.decodeIfPresent(String.self, forKey: .email)
        hasClaudeMax = (try account.decodeIfPresent(Bool.self, forKey: .hasClaudeMax)) ?? false
    }
}
