import Foundation
import UserNotifications

enum Notifier {
    /// 알림 센터는 번들 ID가 있는 .app으로 실행했을 때만 쓸 수 있습니다 (`swift run`에서는 크래시).
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static let reminderPrefix = "reset-reminder-"

    /// 초기화 전 알림을 모두 지우고 새로 예약합니다. 같은 한도는 같은 ID라 중복되지 않습니다.
    static func scheduleResetReminders(_ reminders: [(id: String, title: String, body: String, date: Date)]) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for reminder in reminders {
                let interval = reminder.date.timeIntervalSinceNow
                guard interval > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                center.add(UNNotificationRequest(identifier: reminderPrefix + reminder.id, content: content, trigger: trigger))
            }
        }
    }

    static func cancelResetReminders() {
        scheduleResetReminders([])
    }
}
