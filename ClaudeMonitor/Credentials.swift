//
//  Credentials.swift
//  ClaudeMonitor
//

import Foundation
import Security

struct ClaudeCredentials {
    let accessToken: String
    let expiresAt: Date?
}

enum CredentialsError: Error {
    case notFound      // item / token tidak ada di Keychain
    case unreadable    // item ada tapi gagal di-decode
}

enum Credentials {
    private static let service = "Claude Code-credentials"

    /// Baca token OAuth Claude Code dari Keychain. Memicu prompt izin sekali.
    static func load() throws -> ClaudeCredentials {
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
