import AppKit
import SwiftUI
import UserNotifications

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist의 LSUIElement로도 처리되지만, `swift run`으로 실행할 때도 Dock 아이콘을 숨깁니다.
        NSApp.setActivationPolicy(.accessory)

        #if DEBUG
        DebugSnapshot.runIfRequested()
        #endif

        if Notifier.isAvailable {
            UNUserNotificationCenter.current().delegate = self
            Notifier.removeLegacyScheduledNotifications()
            if UserDefaults.standard.bool(forKey: AppSettings.connected), AppSettings.wantsNotifications {
                Notifier.requestAuthorization()
            }
        }
    }

    // 메뉴바 앱은 대부분 활성 앱이 아니지만, 팝오버가 열려 있을 때도 배너를 보여줍니다.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 소리는 Notifier가 직접 재생하므로 여기서는 배너만 보여 줍니다.
        completionHandler([.banner, .list])
    }
}
