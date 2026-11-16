//
//  Credentials.swift
//  ClaudeMonitor
//

import Foundation
import Security

nonisolated struct ClaudeCredentials {
    let accessToken: String
    let expiresAt: Date?
}

nonisolated enum CredentialsError: Error {
    case notFound      // item / token tidak ada di Keychain
    case unreadable    // item ada tapi gagal di-decode
}

nonisolated enum Credentials {
    /// Daftar nama service semua item Keychain Claude Code. Hanya atribut yang
    /// dibaca (tanpa data/token), jadi tidak memicu prompt izin.
    static func listServices() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        let services = items.compactMap { $0[kSecAttrService as String] as? String }
            .filter(AccountMath.isClaudeService)
        return Array(Set(services))
    }

    /// Baca token OAuth Claude Code item default.
    static func load() throws -> ClaudeCredentials {
        try load(service: AccountMath.defaultService)
    }

    /// Baca token OAuth dari item Keychain `service`. Memicu prompt izin sekali per item.
    /// Hanya accessToken + expiresAt yang dipakai — refreshToken sengaja tidak disentuh.
    static func load(service: String) throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialsError.notFound
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw CredentialsError.unreadable
        }
        var expires: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expires = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = oauth["expiresAt"] as? Int {
            expires = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }
        return ClaudeCredentials(accessToken: token, expiresAt: expires)
    }
}
