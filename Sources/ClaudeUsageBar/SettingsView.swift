import ClaudeUsageCore
import SwiftUI

/// 팝오버 안에서 바로 여는 설정 화면.
/// (메뉴바 전용 앱에서 별도 설정 창을 띄우면 포커스 문제가 잦아 팝오버 안에서 처리합니다.)
struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    let close: () -> Void

    @AppStorage(AppSettings.menuBarStyle) private var styleRaw = MenuBarStyle.sessionAndWeekly.rawValue
    @AppStorage(AppSettings.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(AppSettings.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(AppSettings.resetReminderMinutes) private var resetReminderMinutes = 15
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var language = AppLanguage.override ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                Text("Settings").font(.headline)
                Spacer()
            }

            AccountSection()

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                row("Menu bar") {
                    Picker("", selection: $styleRaw) {
                        ForEach(MenuBarStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                }
                row("Refresh every") {
                    Picker("", selection: $refreshMinutes) {
                        ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }
                row("Reset reminder") {
                    Picker("", selection: $resetReminderMinutes) {
                        Text("Off").tag(0)
                        ForEach(AppSettings.resetReminderOptions.filter { $0 > 0 }, id: \.self) { minutes in
                            Text("\(minutes) min before").tag(minutes)
                        }
                    }
                }
                if resetReminderMinutes > 0 {
                    Text("Only for limits at \(reminderThreshold) or more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                row("Language") {
                    Picker("", selection: $language) {
                        Text("System default").tag("")
                        Divider()
                        ForEach(AppLanguage.supported, id: \.self) { code in
                            Text(verbatim: AppLanguage.nativeName(code)).tag(code)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $notificationsEnabled) {
                    HStack(spacing: 4) {
                        Text("Usage alerts")
                        Text(verbatim: AppSettings.alertThresholds.map { "\($0)%" }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            HStack {
                Text("Version \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let url = AppInfo.repositoryURL {
                    Link("GitHub", destination: url).font(.caption)
                }
            }

            Text("Unofficial app. Not affiliated with Anthropic.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .onChange(of: language) { code in
            AppLanguage.set(code.isEmpty ? nil : code)
        }
        .onChange(of: refreshMinutes) { _ in
            store.startPolling()
        }
        .onChange(of: resetReminderMinutes) { minutes in
            if minutes > 0 { Notifier.requestAuthorization() }
            store.scheduleResetReminders()
        }
        .onChange(of: notificationsEnabled) { enabled in
            if enabled { Notifier.requestAuthorization() }
        }
        .onChange(of: launchAtLogin) { enabled in
            guard enabled != LoginItem.isEnabled else { return }
            do {
                try LoginItem.setEnabled(enabled)
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
                launchAtLogin = LoginItem.isEnabled
            }
        }
    }

    private var reminderThreshold: String {
        MenuBarFormatter.percentText(Double(AppSettings.resetReminderMinimumPercent))
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content().fixedSize()
        }
    }
}

/// 연결된 계정 정보와 연결 / 연결 해제(로그아웃)
private struct AccountSection: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Account")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if store.isConnected {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: store.profile?.displayName ?? store.profile?.email ?? String(localized: "Connected"))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let email = store.profile?.email, email != store.profile?.displayName {
                            Text(verbatim: email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let plan = store.credentials?.planName {
                            Text(verbatim: plan)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Button(role: .destructive) {
                    store.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .controlSize(.small)
                Text("Removes this account's data from the app. Your Claude Code login is not affected.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }
}
