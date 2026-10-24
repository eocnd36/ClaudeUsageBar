import Foundation

/// 메뉴바에 표시할 내용
public enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    /// `79% · 39%`
    case sessionAndWeekly
    /// `79%`
    case sessionOnly
    /// `79% · 1h 20m`
    case sessionAndReset
    /// 게이지 아이콘만
    case iconOnly

    public var id: String { rawValue }
}

public enum MenuBarFormatter {
    public static func percentText(_ percent: Double) -> String {
        "\(Int(percent.rounded()))%"
    }

    /// - Parameter countdown: 남은 시간을 사람이 읽을 수 있는 문자열로 바꾸는 함수 (앱 언어에 맞춰 주입)
    public static func text(
        style: MenuBarStyle,
        snapshot: UsageSnapshot?,
        now: Date,
        countdown: (TimeInterval) -> String
    ) -> String? {
        guard style != .iconOnly else { return nil }
        guard let snapshot, let session = snapshot.limit(.session) else {
            return snapshot == nil ? nil : "–"
        }
        let sessionText = percentText(session.percent)

        switch style {
        case .sessionOnly, .iconOnly:
            return sessionText
        case .sessionAndWeekly:
            guard let weekly = snapshot.limit(.weekly) else { return sessionText }
            return "\(sessionText) · \(percentText(weekly.percent))"
        case .sessionAndReset:
            guard let resetsAt = session.resetsAt, resetsAt > now else { return sessionText }
            return "\(sessionText) · \(countdown(resetsAt.timeIntervalSince(now)))"
        }
    }
}

/// 사용량이 임계값을 넘는 순간을 감지합니다 (알림용).
public struct ThresholdCrossing: Equatable, Sendable {
    public var item: LimitItem
    public var threshold: Int
}

public enum ThresholdDetector {
    /// 이전 스냅샷이 없으면(앱 첫 실행) 알림을 보내지 않습니다 — 실행할 때마다 알림이 쏟아지는 것 방지.
    /// 한도 창이 초기화되었다면(초기화 시각이 바뀜) 이전 값을 0으로 간주합니다.
    public static func crossings(from old: UsageSnapshot?, to new: UsageSnapshot, thresholds: [Int]) -> [ThresholdCrossing] {
        guard let old else { return [] }
        return new.limits.compactMap { item in
            let previous = old.limit(item.kind)
            let previousPercent: Double
            if let previous, sameWindow(previous.resetsAt, item.resetsAt) {
                previousPercent = previous.percent
            } else {
                previousPercent = 0
            }
            let crossed = thresholds.filter { previousPercent < Double($0) && item.percent >= Double($0) }
            return crossed.max().map { ThresholdCrossing(item: item, threshold: $0) }
        }
    }

    private static func sameWindow(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case let (a?, b?): return abs(a.timeIntervalSince(b)) < 60
        case (nil, nil): return true
        default: return false
        }
    }
}

/// 한도가 초기화되기 직전에 보낼 알림 계획.
public struct ResetReminder: Equatable, Sendable {
    public var item: LimitItem
    public var fireDate: Date
}

public enum ResetReminderPlanner {
    /// - Parameters:
    ///   - leadTime: 초기화 몇 초 전에 알릴지
    ///   - minimumPercent: 이 사용률 이상인 한도만 알립니다 (거의 안 쓴 세션까지 매번 알리지 않도록).
    /// 알림 시각이 이미 지났으면 제외합니다 (늦게 울리는 알림 방지).
    public static func reminders(
        for snapshot: UsageSnapshot,
        leadTime: TimeInterval,
        minimumPercent: Double,
        now: Date
    ) -> [ResetReminder] {
        guard leadTime > 0 else { return [] }
        return snapshot.limits.compactMap { item in
            guard item.percent >= minimumPercent, let resetsAt = item.resetsAt else { return nil }
            let fireDate = resetsAt.addingTimeInterval(-leadTime)
            guard fireDate > now else { return nil }
            return ResetReminder(item: item, fireDate: fireDate)
        }
    }
}
