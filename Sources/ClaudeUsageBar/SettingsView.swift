import ClaudeUsageCore
import SwiftUI

/// 팝오버 안에서 바로 여는 설정 화면.
/// (메뉴바 전용 앱에서 별도 설정 창을 띄우면 포커스 문제가 잦아 팝오버 안에서 처리합니다.)
struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore
    let close: () -> Void

    @AppStorage(AppSettings.menuBarStyle) private var styleRaw = MenuBarStyle.sessionAndWeekly.rawValue
    @AppStorage(AppSettings.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(AppSettings.notificationsEnabled) private var usageAlertsEnabled = true
    @AppStorage(AppSettings.alertThresholdsKey) private var thresholdsRaw = "80,95"
    @AppStorage(AppSettings.resetReminderEnabled) private var resetReminderEnabled = true
    @AppStorage(AppSettings.resetReminderMinutes) private var resetReminderMinutes = 15
    @AppStorage(AppSettings.notifyOnReset) private var notifyOnReset = false
    @AppStorage(AppSettings.resetReminderMinimumPercent) private var minimumPercent = 50
    @AppStorage(AppSettings.statusAlertsEnabled) private var statusAlertsEnabled = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var language = AppLanguage.override ?? ""
    @State private var testSent = false

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

            notificationSection

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

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
        .task { await store.refreshNotificationPermission() }
        .onChange(of: language) { code in
            AppLanguage.set(code.isEmpty ? nil : code)
        }
        .onChange(of: refreshMinutes) { _ in
            store.startPolling()
        }
        .onChange(of: resetReminderEnabled) { _ in notificationSettingsChanged() }
        .onChange(of: resetReminderMinutes) { _ in notificationSettingsChanged() }
        .onChange(of: notifyOnReset) { _ in notificationSettingsChanged() }
        .onChange(of: minimumPercent) { _ in notificationSettingsChanged() }
        .onChange(of: usageAlertsEnabled) { _ in notificationSettingsChanged() }
        .onChange(of: statusAlertsEnabled) { _ in notificationSettingsChanged() }
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

    // MARK: - Notifications

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notifications")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if store.notificationsDenied {
                PermissionWarning()
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Usage alerts", isOn: $usageAlertsEnabled)
                if usageAlertsEnabled {
                    ThresholdEditor(raw: $thresholdsRaw)
                        .padding(.leading, 2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Remind before a limit resets", isOn: $resetReminderEnabled)
                if resetReminderEnabled {
                    HStack(spacing: 6) {
                        NumberField(value: $resetReminderMinutes, range: AppSettings.resetReminderMinutesRange)
                        Text("min before")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }

            Toggle("Notify when a limit resets", isOn: $notifyOnReset)

            if resetReminderEnabled || notifyOnReset {
                HStack(spacing: 6) {
                    Text("Only for limits used at least")
                        .foregroundStyle(.secondary)
                    NumberField(value: $minimumPercent, range: AppSettings.minimumPercentRange)
                    Text(verbatim: "%")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Toggle("Alert me when Claude has an outage", isOn: $statusAlertsEnabled)

            Button {
                Notifier.requestAuthorization()
                Notifier.post(
                    title: String(localized: "Test notification"),
                    body: String(localized: "Notifications from Claude Usage Bar are working.")
                )
                testSent = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await store.refreshNotificationPermission()
                    testSent = false
                }
            } label: {
                Label(testSent ? String(localized: "Sent") : String(localized: "Send test notification"), systemImage: "bell")
            }
            .controlSize(.small)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func notificationSettingsChanged() {
        if AppSettings.wantsNotifications { Notifier.requestAuthorization() }
        store.scheduleResetReminders()
        Task { await store.refreshNotificationPermission() }
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content().fixedSize()
        }
    }
}

/// 알림이 꺼져 있을 때 시스템 설정으로 안내합니다.
private struct PermissionWarning: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Notifications are turned off for this app.", systemImage: "bell.slash")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Button("Open Notification Settings") {
                Notifier.openSystemSettings()
            }
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }
}

/// 사용량 알림 기준(%)을 직접 추가하고 지우는 편집기
private struct ThresholdEditor: View {
    @Binding var raw: String
    @State private var draft = ""
    @State private var invalid = false

    private var values: [Int] { AppSettings.parseThresholds(raw) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.self) { value in
                HStack(spacing: 3) {
                    Text(verbatim: "\(value)%").monospacedDigit()
                    Button {
                        raw = AppSettings.formatThresholds(values.filter { $0 != value })
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            if values.count < AppSettings.maxAlertThresholds {
                TextField(text: $draft, prompt: Text(verbatim: "%")) { EmptyView() }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                    .onSubmit(add)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red, lineWidth: invalid ? 1 : 0))
                Button("Add", action: add)
                    .controlSize(.small)
                    .disabled(draft.isEmpty)
            }
        }
    }

    private func add() {
        let trimmed = draft.trimmingCharacters(in: CharacterSet(charactersIn: " %"))
        guard let value = Int(trimmed), (1...100).contains(value) else {
            invalid = true
            return
        }
        raw = AppSettings.formatThresholds(values + [value])
        draft = ""
        invalid = false
    }
}

/// 직접 입력하거나 화살표로 조절하는 숫자 칸. 범위를 벗어나면 가장 가까운 값으로 맞춥니다.
private struct NumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
        .onChange(of: value) { newValue in
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            if clamped != newValue { value = clamped }
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
