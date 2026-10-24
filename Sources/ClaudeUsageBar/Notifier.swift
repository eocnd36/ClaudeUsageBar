import AppKit
import Foundation
import os
import UserNotifications

enum Notifier {
    private static let log = Logger(subsystem: "io.github.claudeusagebar", category: "notifications")

    /// 알림 센터는 번들 ID가 있는 .app으로 실행했을 때만 쓸 수 있습니다 (`swift run`에서는 크래시).
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            log.notice("Authorization status before request: \(settings.authorizationStatus.rawValue)")
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                log.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
            } else {
                log.notice("Authorization granted: \(granted)")
            }
        }
    }

    /// 사용자가 시스템 설정에서 이 앱의 알림을 꺼 두었는지 (또는 macOS가 허용하지 않았는지)
    static func isDenied() async -> Bool {
        guard isAvailable else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .denied
    }

    /// 시스템 설정 → 알림에서 이 앱 항목을 엽니다.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!
        NSWorkspace.shared.open(url)
    }

    static func post(title: String, body: String) {
        add(identifier: UUID().uuidString, title: title, body: body, trigger: nil)
    }

    private static let reminderPrefix = "reset-reminder-"

    /// 초기화 관련 알림을 모두 지우고 새로 예약합니다. 같은 ID는 중복되지 않습니다.
    static func scheduleResetReminders(_ reminders: [(id: String, title: String, body: String, date: Date)]) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for reminder in reminders {
                let interval = reminder.date.timeIntervalSinceNow
                guard interval > 0 else { continue }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                add(identifier: reminderPrefix + reminder.id, title: reminder.title, body: reminder.body, trigger: trigger)
            }
        }
    }

    static func cancelResetReminders() {
        scheduleResetReminders([])
    }

    private static func add(identifier: String, title: String, body: String, trigger: UNNotificationTrigger?) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("Failed to add \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                log.notice("Added \(identifier, privacy: .public)")
            }
        }
    }
}
