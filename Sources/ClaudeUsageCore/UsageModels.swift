import Foundation

// MARK: - Raw API response (GET https://api.anthropic.com/api/oauth/usage)
//
// 비공개 API라서 필드가 언제든 바뀔 수 있습니다. 모든 필드를 optional로 두고
// 개별 필드 디코딩 실패가 전체 실패로 번지지 않게 `try?`로 읽습니다.

public struct UsageResponse: Decodable, Sendable {
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
    public var sevenDayOpus: UsageWindow?
    public var sevenDaySonnet: UsageWindow?
    public var sevenDayCowork: UsageWindow?
    public var extraUsage: ExtraUsage?
    public var sevenDayBreakdown: UsageBreakdown?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
        case sevenDayBreakdown = "seven_day_breakdown"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? c.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        sevenDay = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        sevenDayOpus = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
        sevenDayCowork = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDayCowork)
        extraUsage = try? c.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        sevenDayBreakdown = try? c.decodeIfPresent(UsageBreakdown.self, forKey: .sevenDayBreakdown)
    }
}

public struct UsageWindow: Decodable, Sendable {
    public var utilization: Double?
    public var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try? c.decodeIfPresent(Double.self, forKey: .utilization)
        resetsAt = (try? c.decodeIfPresent(String.self, forKey: .resetsAt)).flatMap { $0.flatMap(ISODate.parse) }
    }
}

public struct ExtraUsage: Decodable, Sendable {
    public var isEnabled: Bool?
    public var utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
    }
}

public struct UsageBreakdown: Decodable, Sendable {
    public struct Row: Decodable, Sendable {
        public var key: String
        public var displayName: String?
        public var percent: Double?

        enum CodingKeys: String, CodingKey {
            case key
            case displayName = "display_name"
            case percent
        }
    }

    public var rows: [Row]?
}

// MARK: - Domain model

public enum LimitKind: String, CaseIterable, Sendable {
    case session
    case weekly
    case weeklyOpus
    case weeklySonnet
    case weeklyCowork

    /// 한도 창의 전체 길이. 진행 속도(페이스) 표시에 사용합니다.
    public var windowDuration: TimeInterval {
        switch self {
        case .session: return 5 * 3600
        default: return 7 * 86400
        }
    }
}

public enum UsageSeverity: Sendable {
    case normal, warning, critical

    public init(percent: Double) {
        switch percent {
        case ..<70: self = .normal
        case ..<90: self = .warning
        default: self = .critical
        }
    }
}

public struct LimitItem: Identifiable, Equatable, Sendable {
    public var kind: LimitKind
    /// 0...100
    public var percent: Double
    public var resetsAt: Date?

    public var id: String { kind.rawValue }
    public var severity: UsageSeverity { UsageSeverity(percent: percent) }

    public init(kind: LimitKind, percent: Double, resetsAt: Date?) {
        self.kind = kind
        self.percent = min(max(percent, 0), 100)
        self.resetsAt = resetsAt
    }

    /// 현재 한도 창에서 경과한 시간 비율 (0...1). 초기화 시각을 모르면 nil.
    public func elapsedFraction(now: Date) -> Double? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(1 - remaining / kind.windowDuration, 0), 1)
    }
}

public struct BreakdownItem: Identifiable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var percent: Double

    public var id: String { key }

    public init(key: String, name: String, percent: Double) {
        self.key = key
        self.name = name
        self.percent = percent
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public var limits: [LimitItem]
    public var breakdown: [BreakdownItem]
    /// 추가 사용량(크레딧)이 켜져 있을 때만 값이 있습니다.
    public var extraUsagePercent: Double?
    public var fetchedAt: Date

    public init(limits: [LimitItem], breakdown: [BreakdownItem] = [], extraUsagePercent: Double? = nil, fetchedAt: Date) {
        self.limits = limits
        self.breakdown = breakdown
        self.extraUsagePercent = extraUsagePercent
        self.fetchedAt = fetchedAt
    }

    public init(response: UsageResponse, fetchedAt: Date) {
        let windows: [(LimitKind, UsageWindow?)] = [
            (.session, response.fiveHour),
            (.weekly, response.sevenDay),
            (.weeklyOpus, response.sevenDayOpus),
            (.weeklySonnet, response.sevenDaySonnet),
            (.weeklyCowork, response.sevenDayCowork),
        ]
        limits = windows.compactMap { kind, window in
            guard let window, let utilization = window.utilization else { return nil }
            return LimitItem(kind: kind, percent: utilization, resetsAt: window.resetsAt)
        }
        breakdown = (response.sevenDayBreakdown?.rows ?? []).compactMap { row in
            guard let percent = row.percent, percent > 0 else { return nil }
            return BreakdownItem(key: row.key, name: row.displayName ?? row.key, percent: percent)
        }
        if response.extraUsage?.isEnabled == true {
            extraUsagePercent = response.extraUsage?.utilization ?? 0
        } else {
            extraUsagePercent = nil
        }
        self.fetchedAt = fetchedAt
    }

    public func limit(_ kind: LimitKind) -> LimitItem? {
        limits.first { $0.kind == kind }
    }
}

// MARK: - Date parsing

public enum ISODate {
    /// `2026-10-24T04:00:00.121919+00:00`처럼 마이크로초가 붙은 값도 파싱합니다.
    public static func parse(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: string) { return date }

        // 소수점 이하 자릿수가 많아 실패한 경우 밀리초까지만 남기고 재시도
        guard let dot = string.firstIndex(of: ".") else { return nil }
        let afterDot = string[string.index(after: dot)...]
        let digits = afterDot.prefix { $0.isNumber }
        let rest = afterDot.dropFirst(digits.count)
        let trimmed = string[..<dot] + "." + digits.prefix(3) + rest
        return fractional.date(from: String(trimmed))
    }
}
