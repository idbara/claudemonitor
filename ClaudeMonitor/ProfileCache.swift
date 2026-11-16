//
//  ProfileCache.swift
//  ClaudeMonitor
//

import Foundation

/// Profil yang disimpan per item Keychain, supaya akun dengan token
/// kedaluwarsa tetap punya nama/uuid (untuk tampilan & penggabungan).
nonisolated struct CachedProfile: Codable, Equatable {
    let uuid: String?
    let fullName: String?
    let email: String?
    let hasClaudeMax: Bool
}

nonisolated extension CachedProfile {
    init(_ p: Profile) {
        self.init(uuid: p.uuid, fullName: p.fullName, email: p.email, hasClaudeMax: p.hasClaudeMax)
    }
}

nonisolated enum ProfileCache {
    private static func key(_ service: String) -> String { "profile.\(service)" }

    static func get(_ service: String, defaults: UserDefaults = .standard) -> CachedProfile? {
        guard let data = defaults.data(forKey: key(service)) else { return nil }
        return try? JSONDecoder().decode(CachedProfile.self, from: data)
    }

    static func set(_ p: CachedProfile, for service: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(p) { defaults.set(data, forKey: key(service)) }
    }
}
