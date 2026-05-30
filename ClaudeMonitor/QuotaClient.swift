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
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Ambil kuota dari Anthropic memakai access token OAuth.
    static func fetch(accessToken: String) async throws -> QuotaUsage {
        var req = URLRequest(url: endpoint)
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
        do {
            return try JSONDecoder().decode(QuotaUsage.self, from: data)
        } catch {
            throw QuotaClientError.badResponse
        }
    }
}
