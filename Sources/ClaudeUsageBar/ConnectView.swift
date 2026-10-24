import SwiftUI

/// 연결 전 첫 화면. 사용자가 직접 "연결"을 눌러야 이 앱이 Claude Code 로그인 정보를 읽기 시작합니다.
struct ConnectView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: GaugeIcon.image(percent: 65))
                .resizable()
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text("Connect your Claude account")
                .font(.headline)

            Text("See the usage of the Claude account you're signed in to with Claude Code. Your login stays on this Mac and is only sent to Anthropic.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            loginStatus

            Button {
                store.connect()
            } label: {
                Text("Connect").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.claudeCodeLoginFound != true)
        }
        .frame(maxWidth: .infinity)
        .task { await store.checkClaudeCodeLogin() }
    }

    @ViewBuilder
    private var loginStatus: some View {
        switch store.claudeCodeLoginFound {
        case nil:
            ProgressView().controlSize(.small)
        case true?:
            Label("Claude Code login found", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case false?:
            VStack(spacing: 6) {
                Label("No Claude Code login found", systemImage: "xmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                Text(.init(String(localized: "Install Claude Code and run `claude` in Terminal to sign in, then check again.")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Link(String(localized: "Claude Code setup guide"), destination: AppInfo.claudeCodeDocsURL)
                    Button(String(localized: "Check again")) {
                        Task { await store.checkClaudeCodeLogin() }
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        }
    }
}
