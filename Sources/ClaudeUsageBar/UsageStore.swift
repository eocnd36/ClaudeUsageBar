import AppKit
import ClaudeUsageCore
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    /// 사용자가 "연결"을 눌러 이 앱이 Claude Code 로그인 정보를 쓰도록 허락했는지
    @Published private(set) var isConnected: Bool
    /// 연결 화면에서 보여 줄, 이 Mac에 Claude Code 로그인 정보가 있는지 여부 (nil = 확인 전)
    @Published private(set) var claudeCodeLoginFound: Bool?
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var credentials: ClaudeCredentials?
    @Published private(set) var profile: AccountProfile?
    @Published private(set) var error: UsageError?
    @Published private(set) var isRefreshing = false
    /// 남은 시간 표시를 갱신하기 위한 시계 (30초마다)
    @Published private(set) var now = Date()

    private let client = UsageClient(
        userAgent: "ClaudeUsageBar/\(AppInfo.version)",
        languages: Bundle.main.preferredLocalizations
    )
    private let loader = CredentialLoader()
    private var pollTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var lastAttempt: Date?
    private var backoffUntil: Date?
    private var profileToken: String?
    /// 연결 해제 시 증가. 해제 전에 시작된 요청의 결과가 뒤늦게 반영되지 않게 합니다.
    private var generation = 0

    init() {
        isConnected = UserDefaults.standard.bool(forKey: AppSettings.connected)
        if isConnected {
            startPolling()
        }

        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * NSEC_PER_SEC)
                self?.now = Date()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // 잠자기 해제 직후에는 네트워크가 아직 안 붙어 있을 수 있어 잠시 기다립니다.
                try? await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)
                await self?.refresh(force: true)
            }
        }
    }

    #if DEBUG
    /// 스크린샷용: 네트워크 없이 주어진 데이터로 채웁니다.
    init(preview snapshot: UsageSnapshot, credentials: ClaudeCredentials, profile: AccountProfile) {
        isConnected = true
        self.snapshot = snapshot
        self.credentials = credentials
        self.profile = profile
        now = snapshot.fetchedAt
    }
    #endif

    // MARK: - Connection

    func checkClaudeCodeLogin() async {
        let loader = self.loader
        claudeCodeLoginFound = await Task.detached { (try? loader.load()) != nil }.value
    }

    func connect() {
        UserDefaults.standard.set(true, forKey: AppSettings.connected)
        isConnected = true
        if AppSettings.wantsNotifications {
            Notifier.requestAuthorization()
        }
        startPolling()
    }

    /// 앱과 계정의 연결을 끊고 메모리에 있던 사용량·계정 정보를 모두 지웁니다.
    /// Claude Code 자체의 로그인은 건드리지 않습니다.
    func disconnect() {
        UserDefaults.standard.set(false, forKey: AppSettings.connected)
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        isConnected = false
        isRefreshing = false
        snapshot = nil
        credentials = nil
        profile = nil
        profileToken = nil
        error = nil
        lastAttempt = nil
        backoffUntil = nil
        claudeCodeLoginFound = nil
        Notifier.cancelResetReminders()
    }

    // MARK: - Polling

    /// 새로고침 간격이 바뀌면 다시 호출합니다.
    func startPolling() {
        pollTask?.cancel()
        guard isConnected else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(force: true)
                let delay = self.nextDelay()
                try? await Task.sleep(nanoseconds: UInt64(delay * Double(NSEC_PER_SEC)))
            }
        }
    }

    /// - Parameter force: false면 최근 60초 안에 시도했을 때 건너뜁니다 (팝오버를 열 때마다 호출되므로).
    func refresh(force: Bool) async {
        guard isConnected, !isRefreshing else { return }
        if !force, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        if let backoffUntil, Date() < backoffUntil { return }

        let generation = self.generation
        isRefreshing = true
        lastAttempt = Date()
        defer {
            if generation == self.generation {
                isRefreshing = false
                now = Date()
            }
        }

        do {
            // 키체인 조회는 프로세스를 띄우므로 메인 스레드 밖에서 실행합니다.
            // Claude Code가 토큰을 갱신했을 수 있으니 매번 새로 읽습니다.
            let loader = self.loader
            let credentials = try await Task.detached { try loader.load() }.value
            guard generation == self.generation else { return }
            self.credentials = credentials

            let response = try await client.fetch(token: credentials.accessToken)
            guard generation == self.generation else { return }
            let newSnapshot = UsageSnapshot(response: response, fetchedAt: Date())
            notifyIfNeeded(old: snapshot, new: newSnapshot)
            snapshot = newSnapshot
            scheduleResetReminders()
            error = nil
            backoffUntil = nil

            // 계정 정보는 토큰이 바뀌었을 때만 다시 불러옵니다 (실패해도 사용량 표시에는 영향 없음).
            if profileToken != credentials.accessToken,
               let profile = try? await client.fetchProfile(token: credentials.accessToken),
               generation == self.generation {
                self.profile = profile
                profileToken = credentials.accessToken
            }
        } catch {
            guard generation == self.generation else { return }
            switch error {
            case let usageError as UsageError:
                self.error = usageError
                if case let .rateLimited(retryAfter) = usageError {
                    backoffUntil = Date().addingTimeInterval(max(retryAfter ?? 300, 60))
                }
            case is CredentialError:
                credentials = nil
                profile = nil
                self.error = .notLoggedIn
            default:
                self.error = .network(error.localizedDescription)
            }
        }
    }

    var session: LimitItem? { snapshot?.limit(.session) }

    private func nextDelay() -> TimeInterval {
        if let backoffUntil {
            return max(backoffUntil.timeIntervalSinceNow, 30)
        }
        return AppSettings.refreshInterval
    }

    /// 현재 스냅샷 기준으로 초기화 전 알림을 다시 예약합니다. 설정이 바뀌었을 때도 호출합니다.
    func scheduleResetReminders() {
        let minutes = UserDefaults.standard.integer(forKey: AppSettings.resetReminderMinutes)
        guard isConnected, let snapshot, minutes > 0 else {
            Notifier.cancelResetReminders()
            return
        }
        let reminders = ResetReminderPlanner.reminders(
            for: snapshot,
            leadTime: TimeInterval(minutes * 60),
            minimumPercent: Double(AppSettings.resetReminderMinimumPercent),
            now: Date()
        )
        Notifier.scheduleResetReminders(reminders.map { reminder in
            let item = reminder.item
            let remaining = Formatters.countdown(TimeInterval(minutes * 60))
            let percent = MenuBarFormatter.percentText(item.percent)
            return (
                id: item.kind.rawValue,
                title: String(localized: "\(item.kind.title) resets in \(remaining)"),
                body: String(localized: "Currently at \(percent). Your usage will be available again soon."),
                date: reminder.fireDate
            )
        })
    }

    private func notifyIfNeeded(old: UsageSnapshot?, new: UsageSnapshot) {
        guard UserDefaults.standard.bool(forKey: AppSettings.notificationsEnabled) else { return }
        for crossing in ThresholdDetector.crossings(from: old, to: new, thresholds: AppSettings.alertThresholds) {
            let item = crossing.item
            let percent = MenuBarFormatter.percentText(Double(crossing.threshold))
            let title = String(localized: "\(item.kind.title) reached \(percent)")
            Notifier.post(title: title, body: Formatters.resetDescription(item.resetsAt, now: Date()))
        }
    }
}
