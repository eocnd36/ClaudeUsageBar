import AppKit
import ClaudeUsageCore
import Foundation
import ServiceManagement

enum AppSettings {
    static let menuBarStyle = "menuBarStyle"
    static let refreshMinutes = "refreshMinutes"
    static let notificationsEnabled = "notificationsEnabled"
    static let connected = "connected"
    static let resetReminderMinutes = "resetReminderMinutes"

    static let refreshOptions = [1, 2, 5, 10, 15, 30]
    static let alertThresholds = [80, 95]
    /// 0 = 끔
    static let resetReminderOptions = [0, 5, 15, 30, 60]
    /// 이 사용률 미만인 한도는 초기화 알림을 보내지 않습니다.
    static let resetReminderMinimumPercent = 50

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            menuBarStyle: MenuBarStyle.sessionAndWeekly.rawValue,
            refreshMinutes: 5,
            notificationsEnabled: true,
            connected: false,
            resetReminderMinutes: 15,
        ])
    }

    /// 사용량 알림이나 초기화 알림 중 하나라도 켜져 있으면 알림 권한이 필요합니다.
    static var wantsNotifications: Bool {
        UserDefaults.standard.bool(forKey: notificationsEnabled)
            || UserDefaults.standard.integer(forKey: resetReminderMinutes) > 0
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
