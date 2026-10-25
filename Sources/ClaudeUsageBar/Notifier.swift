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
        add(identifier: UUID().uuidString, title: title, body: body)
        playSound()
    }

    /// Apple 정식 서명이 없는 앱은 macOS가 알림 소리를 빼 버리는 경우가 있어, 소리는 앱이 직접 재생합니다.
    private static func playSound() {
        guard UserDefaults.standard.bool(forKey: AppSettings.notificationSound) else { return }
        DispatchQueue.main.async {
            (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
        }
    }

    /// 예약해 둔 초기화 알림. 시스템 예약 알림은 소리를 직접 낼 수 없어 앱이 시각을 재다가 보냅니다.
    /// (메뉴 막대 앱이라 항상 실행 중이고, 잠자기에서 깨어나면 다시 예약됩니다.)
    @MainActor private static var scheduled: [String: Task<Void, Never>] = [:]

    /// 초기화 관련 알림을 모두 지우고 새로 예약합니다. 같은 ID는 중복되지 않습니다.
    @MainActor
    static func scheduleResetReminders(_ reminders: [(id: String, title: String, body: String, date: Date)]) {
        scheduled.values.forEach { $0.cancel() }
        scheduled = [:]
        for reminder in reminders {
            let interval = reminder.date.timeIntervalSinceNow
            guard interval > 0 else { continue }
            scheduled[reminder.id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(interval * Double(NSEC_PER_SEC)))
                guard !Task.isCancelled else { return }
                // 잠자기 등으로 많이 늦었다면 지난 알림은 보내지 않습니다.
                guard Date().timeIntervalSince(reminder.date) < 5 * 60 else { return }
                post(title: reminder.title, body: reminder.body)
            }
        }
    }

    /// 1.1.0 이전에는 초기화 알림을 시스템에 예약했습니다. 지금은 앱이 직접 보내므로 남은 예약을 지웁니다.
    static func removeLegacyScheduledNotifications() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    @MainActor
    static func cancelResetReminders() {
        scheduleResetReminders([])
    }

    private static func add(identifier: String, title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("Failed to add \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                log.notice("Added \(identifier, privacy: .public)")
            }
        }
    }
}
