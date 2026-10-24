import AppKit
import ClaudeUsageCore
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var store: UsageStore
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView { showingSettings = false }
            } else {
                UsageView { showingSettings = true }
            }
        }
        .frame(width: 320)
        .task { await store.refresh(force: false) }
    }
}

// MARK: - Usage page

private struct UsageView: View {
    @EnvironmentObject private var store: UsageStore
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !store.isConnected {
                ConnectView()
            } else if let snapshot = store.snapshot {
                if let error = store.error {
                    ErrorBanner(error: error)
                }
                ForEach(snapshot.limits) { item in
                    LimitRow(item: item, now: store.now)
                }
                if let extra = snapshot.extraUsagePercent {
                    ExtraUsageRow(percent: extra)
                }
                if !snapshot.breakdown.isEmpty {
                    Divider()
                    BreakdownView(items: snapshot.breakdown)
                }
            } else if let error = store.error {
                ErrorStateView(error: error)
            } else {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 24)
            }

            Divider()
            footer
        }
        .padding(16)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Claude Usage")
                .font(.headline)
            if let plan = store.credentials?.planName {
                Text(plan)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            if store.isConnected {
                refreshButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh(force: true) }
        } label: {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(IconButtonStyle())
        .disabled(store.isRefreshing)
        .help(Text("Refresh"))
    }

    private var footer: some View {
        HStack {
            Text(Formatters.updatedDescription(store.snapshot?.fetchedAt, now: store.now))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .help(Text("Settings"))
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(IconButtonStyle())
            .help(Text("Quit"))
        }
    }
}

// MARK: - Rows

private struct LimitRow: View {
    let item: LimitItem
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.kind.title)
                        .font(.subheadline.weight(.medium))
                    Text(item.kind.windowLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(MenuBarFormatter.percentText(item.percent))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.severity.color)
            }
            UsageBar(percent: item.percent, color: item.severity.color, pace: item.elapsedFraction(now: now))
            Text(Formatters.resetDescription(item.resetsAt, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ExtraUsageRow: View {
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Extra usage")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(MenuBarFormatter.percentText(percent))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            UsageBar(percent: percent, color: .purple, pace: nil)
        }
    }
}

/// 사용량 막대. `pace`는 한도 창에서 경과한 시간 비율로, 세로 눈금으로 표시합니다.
/// 막대가 눈금보다 앞서 있으면 평소보다 빠르게 쓰고 있다는 뜻입니다.
private struct UsageBar: View {
    let percent: Double
    let color: Color
    let pace: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(geo.size.width * percent / 100, percent > 0 ? 6 : 0))
                if let pace {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2, height: 12)
                        .offset(x: min(max(geo.size.width * pace - 1, 0), geo.size.width - 2))
                        .help(Text("Time elapsed in this window"))
                }
            }
        }
        .frame(height: 8)
    }
}

private struct BreakdownView: View {
    let items: [BreakdownItem]

    private static let palette: [Color] = [.orange, .blue, .purple, .teal, .pink, .gray]

    private func color(at index: Int) -> Color {
        Self.palette[index % Self.palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This week by product")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let total = max(items.reduce(0) { $0 + $1.percent }, 1)
                HStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(at: index))
                            .frame(width: max((geo.size.width - CGFloat(items.count - 1) * 2) * item.percent / total, 2))
                    }
                }
            }
            .frame(height: 6)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 5) {
                        Circle().fill(color(at: index)).frame(width: 7, height: 7)
                        Text(item.name).font(.caption)
                        Text(MenuBarFormatter.percentText(item.percent))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Errors

private extension UsageError {
    var symbol: String {
        switch self {
        case .notLoggedIn: return "person.crop.circle.badge.questionmark"
        case .unauthorized: return "key"
        case .rateLimited: return "hourglass"
        case .network: return "wifi.exclamationmark"
        case .server, .decoding: return "exclamationmark.triangle"
        }
    }

    var title: String {
        switch self {
        case .notLoggedIn: return String(localized: "Claude Code login not found")
        case .unauthorized: return String(localized: "Login expired")
        case .rateLimited: return String(localized: "Too many requests")
        case .network: return String(localized: "Can't reach Claude")
        case let .server(code): return String(localized: "Server error (\(code))")
        case .decoding: return String(localized: "Unexpected response")
        }
    }

    var message: String {
        switch self {
        case .notLoggedIn:
            return String(localized: "This app uses the login saved by Claude Code. Install Claude Code and run `claude` in Terminal to sign in.")
        case .unauthorized:
            return String(localized: "Run `claude` in Terminal once — Claude Code will refresh the login automatically.")
        case .rateLimited:
            return String(localized: "Will retry automatically in a few minutes.")
        case let .network(detail):
            return detail
        case .server:
            return String(localized: "Will retry automatically.")
        case .decoding:
            return String(localized: "The usage format may have changed. Check for an app update.")
        }
    }
}

private struct ErrorStateView: View {
    let error: UsageError

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: error.symbol)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(error.title)
                .font(.subheadline.weight(.semibold))
            Text(.init(error.message))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if error == .notLoggedIn {
                Link(String(localized: "Claude Code setup guide"), destination: AppInfo.claudeCodeDocsURL)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct ErrorBanner: View {
    let error: UsageError

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: error.symbol)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(.caption.weight(.semibold))
                Text(.init(error.message))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }
}

/// 순수 SwiftUI 아이콘 버튼 (AppKit 컨트롤이 아니라서 스냅샷 렌더링에도 그대로 나옵니다)
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
