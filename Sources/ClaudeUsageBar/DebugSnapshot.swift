#if DEBUG
import AppKit
import ClaudeUsageCore
import SwiftUI

/// 디버그 빌드 전용: 팝오버를 PNG로 저장하고 종료합니다. README 스크린샷이나 레이아웃 확인용.
///
///   swift run ClaudeUsageBar --render-snapshot ./docs          # 내 실제 사용량
///   swift run ClaudeUsageBar --render-snapshot ./docs --demo   # 가짜 데모 데이터 (공개용)
enum DebugSnapshot {
    @MainActor
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--render-snapshot"), index + 1 < args.count else { return }
        let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        let demo = args.contains("--demo")

        Task { @MainActor in
            let store: UsageStore
            if demo {
                store = demoStore()
            } else {
                store = UsageStore()
                while store.snapshot == nil && store.error == nil {
                    try? await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)
                }
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for scheme in [ColorScheme.light, .dark] {
                // ScrollView는 ImageRenderer가 그리지 못하므로 사용량 화면만 렌더링합니다.
                let view = UsageView {}
                    .frame(width: 320)
                    .environmentObject(store)
                    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard
                    let image = renderer.nsImage,
                    let tiff = image.tiffRepresentation,
                    let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else { continue }
                let url = directory.appendingPathComponent("popover-\(scheme == .dark ? "dark" : "light").png")
                try? png.write(to: url)
                print("✓ \(url.path)")
            }
            exit(0)
        }
    }

    @MainActor
    private static func demoStore() -> UsageStore {
        let now = Date()
        let snapshot = UsageSnapshot(
            limits: [
                LimitItem(kind: .session, percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60)),
                LimitItem(kind: .weekly, percent: 63, resetsAt: now.addingTimeInterval(2 * 86400 + 5 * 3600)),
                LimitItem(kind: .weeklyOpus, percent: 91, resetsAt: now.addingTimeInterval(2 * 86400 + 5 * 3600)),
            ],
            breakdown: [
                BreakdownItem(key: "claude_code", name: "Claude Code", percent: 58),
                BreakdownItem(key: "chat", name: "Chat", percent: 35),
                BreakdownItem(key: "cowork", name: "Cowork", percent: 7),
            ],
            fetchedAt: now
        )
        return UsageStore(
            preview: snapshot,
            credentials: ClaudeCredentials(accessToken: "demo", subscriptionType: "max", rateLimitTier: "default_claude_max_5x"),
            profile: AccountProfile(email: "you@example.com", displayName: "Demo User")
        )
    }
}
#endif
