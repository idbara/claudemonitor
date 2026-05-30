//
//  QuotaClient.swift
//  ClaudeMonitor
//

import Foundation

enum QuotaClientError: Error {
    case unauthorized          // 401/403 — token ditolak
    case badResponse           // status non-2xx lain / body tak terbaca
    case network(Error)        // gangguan transport
}

enum QuotaClient {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    /// Ambil kuota dari Anthropic memakai access token OAuth.
    static func fetch(accessToken: String) async throws -> QuotaUsage {
        let data = try await get(usageURL, accessToken: accessToken)
        do {
            return try JSONDecoder().decode(QuotaUsage.self, from: data)
        } catch {
            throw QuotaClientError.badResponse
        }
    }

    /// Ambil profil akun (nama, email, status Max).
    static func fetchProfile(accessToken: String) async throws -> Profile {
        let data = try await get(profileURL, accessToken: accessToken)
        do {
            return try JSONDecoder().decode(Profile.self, from: data)
        } catch {
            throw QuotaClientError.badResponse
        }
    }

    /// GET ber-OAuth ke endpoint Anthropic; map status ke QuotaClientError.
    private static func get(_ url: URL, accessToken: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("ClaudeMonitor", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw QuotaClientError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw QuotaClientError.badResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw QuotaClientError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw QuotaClientError.badResponse
        }
        return data
    }
}
