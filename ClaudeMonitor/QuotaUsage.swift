//
//  QuotaUsage.swift
//  ClaudeMonitor
//

import Foundation

/// Satu window kuota (mis. 5 jam / 7 hari).
struct QuotaWindow: Decodable {
    let utilization: Double
    let resetsAt: Date?

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try c.decodeIfPresent(Double.self, forKey: .utilization) ?? 0
        if let s = try c.decodeIfPresent(String.self, forKey: .resetsAt) {
            resetsAt = QuotaWindow.parseDate(s)
        } else {
            resetsAt = nil
        }
    }

    /// resets_at punya fractional seconds + offset, mis. "2026-05-30T17:50:01.019646+00:00".
    static func parseDate(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}

/// Hanya window yang kita pakai; sisanya di respons diabaikan.
struct QuotaUsage: Decodable {
    let fiveHour: QuotaWindow?
    let sevenDay: QuotaWindow?
    let sevenDaySonnet: QuotaWindow?
    let sevenDayOpus: QuotaWindow?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
    }
}
