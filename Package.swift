// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
    ],
    targets: [
        // UI 없는 순수 로직 (API 모델, 인증 정보, 포맷팅) — 테스트 대상
        .target(name: "ClaudeUsageCore"),
        // 메뉴바 앱 (SwiftUI MenuBarExtra)
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageCore"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"]
        ),
    ]
)
