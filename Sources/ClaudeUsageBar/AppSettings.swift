import AppKit
import ClaudeUsageCore
import Foundation
import ServiceManagement

enum AppSettings {
    static let menuBarStyle = "menuBarStyle"
    static let refreshMinutes = "refreshMinutes"
    static let connected = "connected"
    /// 사용량 알림 켜기/끄기와 기준 (쉼표로 구분한 퍼센트, 예: "80,95")
    static let notificationsEnabled = "notificationsEnabled"
    static let alertThresholdsKey = "alertThresholds"
    /// 초기화 전 알림 / 초기화되면 알림, 그리고 두 알림에 공통으로 쓰는 최소 사용률
    static let resetReminderEnabled = "resetReminderEnabled"
    static let resetReminderMinutes = "resetReminderMinutes"
    static let notifyOnReset = "notifyOnReset"
    static let resetReminderMinimumPercent = "resetReminderMinimumPercent"
    /// Claude 장애 알림
    static let statusAlertsEnabled = "statusAlertsEnabled"
    /// 알림과 함께 소리를 낼지
    static let notificationSound = "notificationSound"

    static let refreshOptions = [1, 2, 5, 10, 15, 30]
    static let maxAlertThresholds = 5
    static let resetReminderMinutesRange = 1...720
    static let minimumPercentRange = 0...100

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            menuBarStyle: MenuBarStyle.sessionAndWeekly.rawValue,
            refreshMinutes: 5,
            connected: false,
            notificationsEnabled: true,
            alertThresholdsKey: "80,95",
            resetReminderEnabled: true,
            resetReminderMinutes: 15,
            notifyOnReset: false,
            resetReminderMinimumPercent: 50,
            statusAlertsEnabled: true,
            notificationSound: true,
        ])
        // 1.0.0에서는 "0분 전"이 꺼짐을 뜻했습니다.
        if defaults.object(forKey: resetReminderMinutes) != nil, defaults.integer(forKey: resetReminderMinutes) == 0 {
            defaults.set(false, forKey: resetReminderEnabled)
            defaults.set(15, forKey: resetReminderMinutes)
        }
    }

    static var alertThresholds: [Int] {
        parseThresholds(UserDefaults.standard.string(forKey: alertThresholdsKey) ?? "")
    }

    static func parseThresholds(_ string: String) -> [Int] {
        let values = string.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return Array(Set(values.filter { (1...100).contains($0) })).sorted()
    }

    static func formatThresholds(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ",")
    }

    /// 알림을 하나라도 쓰면 알림 권한이 필요합니다.
    static var wantsNotifications: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: notificationsEnabled)
            || defaults.bool(forKey: resetReminderEnabled)
            || defaults.bool(forKey: notifyOnReset)
            || defaults.bool(forKey: statusAlertsEnabled)
    }

    static var refreshInterval: TimeInterval {
        let minutes = UserDefaults.standard.integer(forKey: refreshMinutes)
        return TimeInterval(max(minutes, 1)) * 60
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// 빌드 스크립트가 Info.plist에 넣어 주는 저장소 주소 (CI에서는 자동으로 현재 저장소)
    static var repositoryURL: URL? {
        guard
            let string = Bundle.main.object(forInfoDictionaryKey: "ClaudeUsageBarRepositoryURL") as? String,
            !string.isEmpty
        else { return nil }
        return URL(string: string)
    }

    static let claudeCodeDocsURL = URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!
    static let claudeUsageURL = URL(string: "https://claude.ai/settings/usage")!
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// 앱 표시 언어. 기본은 시스템 언어를 따르고, 설정에서 바꾸면 앱을 다시 실행합니다.
enum AppLanguage {
    /// Resources/*.lproj 와 같은 목록
    static let supported = ["en", "ko", "ja", "zh-Hans", "zh-Hant", "es", "fr", "de", "it", "pt-BR", "ru"]

    private static let key = "AppleLanguages"

    /// 사용자가 앱에서 직접 고른 언어 (nil = 시스템 설정 따름)
    static var override: String? {
        guard let domain = Bundle.main.bundleIdentifier else { return nil }
        return (UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String])?.first
    }

    /// 각 언어 이름을 그 언어로 표시합니다 (예: 한국어, 日本語).
    static func nativeName(_ code: String) -> String {
        let locale = Locale(identifier: code)
        let name = locale.localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    static func set(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
        relaunch()
    }

    private static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
