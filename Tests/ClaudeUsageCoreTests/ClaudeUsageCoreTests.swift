import Foundation
import Testing
@testable import ClaudeUsageCore

/// 실제 응답에서 필요한 부분만 남긴 픽스처 (코드명 필드 일부 포함)
private let sampleResponse = """
{
  "five_hour": { "utilization": 79.0, "resets_at": "2026-10-24T04:00:00.121919+00:00", "limit_dollars": null },
  "seven_day": { "utilization": 39.0, "resets_at": "2026-10-28T14:00:00.121933+00:00" },
  "seven_day_opus": null,
  "seven_day_sonnet": { "utilization": 12.5, "resets_at": "2026-10-28T14:00:00+00:00" },
  "iguana_necktie": { "utilization": 0.0, "resets_at": "2026-11-05T07:59:00+00:00", "limit_dollars": 100 },
  "extra_usage": { "is_enabled": false, "utilization": null },
  "seven_day_breakdown": {
    "rows": [
      { "key": "claude_code", "display_name": "Claude Code", "percent": 71 },
      { "key": "chat", "display_name": "Chats", "percent": 25 },
      { "key": "other", "display_name": "Other", "percent": 0 }
    ]
  }
}
"""

private func decodeSample() throws -> UsageResponse {
    try JSONDecoder().decode(UsageResponse.self, from: Data(sampleResponse.utf8))
}

@Suite struct DecodingTests {
    @Test func decodesKnownWindows() throws {
        let snapshot = UsageSnapshot(response: try decodeSample(), fetchedAt: Date())

        #expect(snapshot.limits.map(\.kind) == [.session, .weekly, .weeklySonnet])
        #expect(snapshot.limit(.session)?.percent == 79)
        #expect(snapshot.limit(.weekly)?.percent == 39)
        #expect(snapshot.limit(.weeklyOpus) == nil)
        #expect(snapshot.extraUsagePercent == nil)
    }

    @Test func breakdownSkipsZeroRows() throws {
        let snapshot = UsageSnapshot(response: try decodeSample(), fetchedAt: Date())
        #expect(snapshot.breakdown.map(\.name) == ["Claude Code", "Chats"])
    }

    @Test func toleratesUnexpectedShapes() throws {
        let json = #"{ "five_hour": "oops", "seven_day": { "utilization": "x", "resets_at": 5 } }"#
        let response = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        let snapshot = UsageSnapshot(response: response, fetchedAt: Date())
        #expect(snapshot.limits.isEmpty)
    }

    @Test func extraUsageWhenEnabled() throws {
        let json = #"{ "extra_usage": { "is_enabled": true, "utilization": 42.0 } }"#
        let response = try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
        #expect(UsageSnapshot(response: response, fetchedAt: Date()).extraUsagePercent == 42)
    }

    @Test func clampsPercent() {
        #expect(LimitItem(kind: .session, percent: 140, resetsAt: nil).percent == 100)
        #expect(LimitItem(kind: .session, percent: -3, resetsAt: nil).percent == 0)
    }
}

@Suite struct DateTests {
    @Test(arguments: [
        "2026-10-24T04:00:00.121919+00:00",
        "2026-10-24T04:00:00.121+00:00",
        "2026-10-24T04:00:00+00:00",
        "2026-10-24T04:00:00Z",
    ])
    func parsesISOVariants(_ string: String) throws {
        let date = try #require(ISODate.parse(string))
        let expected = Date(timeIntervalSince1970: 1792814400)
        #expect(abs(date.timeIntervalSince(expected)) < 1)
    }

    @Test func rejectsGarbage() {
        #expect(ISODate.parse("tomorrow") == nil)
    }
}

@Suite struct CredentialTests {
    @Test func parsesClaudeCodeFormat() throws {
        let json = #"""
        { "claudeAiOauth": { "accessToken": "tok", "refreshToken": "r", "expiresAt": 1792831746629,
          "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x" }, "organizationUuid": "x" }
        """#
        let credentials = try ClaudeCredentials.parse(Data(json.utf8))
        #expect(credentials.accessToken == "tok")
        #expect(credentials.planName == "Max 20x")
        #expect(credentials.isExpired(now: Date(timeIntervalSince1970: 1792831746)) == false)
        #expect(credentials.isExpired(now: Date(timeIntervalSince1970: 1792831747)) == true)
    }

    @Test func planNameFallsBackToSubscriptionType() {
        #expect(ClaudeCredentials(accessToken: "t", subscriptionType: "pro", rateLimitTier: "default_claude_ai").planName == "Pro")
        #expect(ClaudeCredentials(accessToken: "t").planName == nil)
    }

    @Test func rejectsMissingToken() {
        #expect(throws: CredentialError.malformed) {
            try ClaudeCredentials.parse(Data(#"{ "claudeAiOauth": {} }"#.utf8))
        }
    }

    @Test func readsCredentialsFileFromConfigDir() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let loader = CredentialLoader(environment: ["CLAUDE_CONFIG_DIR": dir.path], home: dir)
        #expect(loader.credentialFiles.first == dir.appendingPathComponent(".credentials.json"))
    }
}

@Suite struct MenuBarTextTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func snapshot(session: Double = 79, weekly: Double? = 39) -> UsageSnapshot {
        var limits = [LimitItem(kind: .session, percent: session, resetsAt: now.addingTimeInterval(4800))]
        if let weekly { limits.append(LimitItem(kind: .weekly, percent: weekly, resetsAt: nil)) }
        return UsageSnapshot(limits: limits, fetchedAt: now)
    }

    func text(_ style: MenuBarStyle, _ snapshot: UsageSnapshot?) -> String? {
        MenuBarFormatter.text(style: style, snapshot: snapshot, now: now) { "\(Int($0 / 60))m" }
    }

    @Test func styles() {
        #expect(text(.sessionAndWeekly, snapshot()) == "79% · 39%")
        #expect(text(.sessionOnly, snapshot()) == "79%")
        #expect(text(.sessionAndReset, snapshot()) == "79% · 80m")
        #expect(text(.iconOnly, snapshot()) == nil)
    }

    @Test func roundsPercent() {
        #expect(text(.sessionOnly, snapshot(session: 79.6)) == "80%")
    }

    @Test func missingData() {
        #expect(text(.sessionAndWeekly, nil) == nil)
        #expect(text(.sessionAndWeekly, snapshot(weekly: nil)) == "79%")
        #expect(text(.sessionAndWeekly, UsageSnapshot(limits: [], fetchedAt: now)) == "–")
    }
}

@Suite struct ThresholdTests {
    let reset = Date(timeIntervalSince1970: 2_000_000)

    func snap(_ percent: Double, resetsAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(limits: [LimitItem(kind: .session, percent: percent, resetsAt: resetsAt ?? reset)], fetchedAt: Date())
    }

    @Test func noAlertsOnFirstFetch() {
        #expect(ThresholdDetector.crossings(from: nil, to: snap(99), thresholds: [80, 95]).isEmpty)
    }

    @Test func reportsHighestCrossedThreshold() {
        let crossings = ThresholdDetector.crossings(from: snap(70), to: snap(96), thresholds: [80, 95])
        #expect(crossings.map(\.threshold) == [95])
    }

    @Test func doesNotRepeatOnceAbove() {
        #expect(ThresholdDetector.crossings(from: snap(85), to: snap(88), thresholds: [80, 95]).isEmpty)
    }

    @Test func newWindowStartsFromZero() {
        let next = snap(82, resetsAt: reset.addingTimeInterval(5 * 3600))
        let crossings = ThresholdDetector.crossings(from: snap(99), to: next, thresholds: [80, 95])
        #expect(crossings.map(\.threshold) == [80])
    }

    @Test func toleratesResetJitter() {
        let jittered = snap(88, resetsAt: reset.addingTimeInterval(0.4))
        #expect(ThresholdDetector.crossings(from: snap(85), to: jittered, thresholds: [80, 95]).isEmpty)
    }
}

@Suite struct PaceTests {
    @Test func elapsedFraction() {
        let now = Date()
        let item = LimitItem(kind: .session, percent: 10, resetsAt: now.addingTimeInterval(3600))
        let fraction = try! #require(item.elapsedFraction(now: now))
        #expect(abs(fraction - 0.8) < 0.0001)
        #expect(LimitItem(kind: .session, percent: 0, resetsAt: nil).elapsedFraction(now: now) == nil)
    }
}

@Suite struct ProfileTests {
    @Test func decodesProfile() throws {
        let json = #"""
        { "account": { "uuid": "u", "full_name": "Full Name", "display_name": "Nick", "email": "a@example.com" },
          "organization": { "uuid": "o", "name": "Acme" }, "enabled_plugins": [] }
        """#
        let profile = try JSONDecoder().decode(AccountProfile.self, from: Data(json.utf8))
        #expect(profile == AccountProfile(email: "a@example.com", displayName: "Nick", organizationName: "Acme"))
    }

    @Test func fallsBackToFullName() throws {
        let json = #"{ "account": { "full_name": "Full Name" } }"#
        let profile = try JSONDecoder().decode(AccountProfile.self, from: Data(json.utf8))
        #expect(profile.displayName == "Full Name")
        #expect(profile.email == nil)
    }

    @Test func acceptLanguageHeader() {
        #expect(UsageClient.acceptLanguage([]) == nil)
        #expect(UsageClient.acceptLanguage(["ko"]) == "ko")
        #expect(UsageClient.acceptLanguage(["ja", "en"]) == "ja, en;q=0.9")
    }
}

@Suite struct ResetReminderTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func plan(_ items: [LimitItem], lead: TimeInterval = 900) -> [ResetReminder] {
        ResetReminderPlanner.reminders(
            for: UsageSnapshot(limits: items, fetchedAt: now), leadTime: lead, minimumPercent: 50, now: now
        )
    }

    @Test func schedulesBeforeReset() {
        let reset = now.addingTimeInterval(3600)
        let reminders = plan([LimitItem(kind: .session, percent: 80, resetsAt: reset)])
        #expect(reminders.map(\.fireDate) == [reset.addingTimeInterval(-900)])
    }

    @Test func skipsLowUsage() {
        #expect(plan([LimitItem(kind: .session, percent: 49, resetsAt: now.addingTimeInterval(3600))]).isEmpty)
    }

    @Test func skipsWhenFireDatePassed() {
        #expect(plan([LimitItem(kind: .session, percent: 90, resetsAt: now.addingTimeInterval(600))]).isEmpty)
    }

    @Test func skipsUnknownResetAndDisabled() {
        #expect(plan([LimitItem(kind: .session, percent: 90, resetsAt: nil)]).isEmpty)
        #expect(plan([LimitItem(kind: .session, percent: 90, resetsAt: now.addingTimeInterval(3600))], lead: -1).isEmpty)
    }

    @Test func zeroLeadFiresAtReset() {
        let reset = now.addingTimeInterval(3600)
        #expect(plan([LimitItem(kind: .session, percent: 90, resetsAt: reset)], lead: 0).map(\.fireDate) == [reset])
    }

    @Test func coversEachEligibleLimit() {
        let reminders = plan([
            LimitItem(kind: .session, percent: 70, resetsAt: now.addingTimeInterval(7200)),
            LimitItem(kind: .weekly, percent: 30, resetsAt: now.addingTimeInterval(86400)),
            LimitItem(kind: .weeklyOpus, percent: 95, resetsAt: now.addingTimeInterval(86400)),
        ])
        #expect(reminders.map(\.item.kind) == [.session, .weeklyOpus])
    }
}


@Suite struct ProjectionTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func projectsHitBeforeReset() throws {
        // 5시간 창 중 2시간 경과, 60% 사용 → 30%/h → 남은 40%는 80분 뒤
        let item = LimitItem(kind: .session, percent: 60, resetsAt: now.addingTimeInterval(3 * 3600))
        let hit = try #require(item.projectedLimitDate(now: now))
        #expect(abs(hit.timeIntervalSince(now) - 80 * 60) < 1)
    }

    @Test func nilWhenOnPace() {
        // 2시간 경과, 30% → 5시간 끝에 75%
        let item = LimitItem(kind: .session, percent: 30, resetsAt: now.addingTimeInterval(3 * 3600))
        #expect(item.projectedLimitDate(now: now) == nil)
    }

    @Test func nilTooEarlyOrAtLimit() {
        let early = LimitItem(kind: .session, percent: 20, resetsAt: now.addingTimeInterval(5 * 3600 - 600))
        #expect(early.projectedLimitDate(now: now) == nil)
        let full = LimitItem(kind: .session, percent: 100, resetsAt: now.addingTimeInterval(3600))
        #expect(full.projectedLimitDate(now: now) == nil)
        #expect(LimitItem(kind: .session, percent: 50, resetsAt: nil).projectedLimitDate(now: now) == nil)
    }
}

@Suite struct ServiceStatusTests {
    let sample = """
    { "page": { "name": "Claude" },
      "status": { "indicator": "minor", "description": "Partially Degraded Service" },
      "components": [],
      "incidents": [
        { "id": "a1", "name": "Elevated errors on Claude Opus", "status": "investigating", "shortlink": "https://stspg.io/x" },
        { "id": "b2", "name": "Old issue", "status": "resolved" }
      ] }
    """

    @Test func parsesSummary() throws {
        let status = try StatusClient.parse(Data(sample.utf8))
        #expect(status.level == .minor)
        #expect(status.summary == "Partially Degraded Service")
        #expect(status.incidents.map(\.id) == ["a1"])
        #expect(status.hasProblem)
    }

    @Test func operational() throws {
        let json = #"{ "status": { "indicator": "none", "description": "All Systems Operational" }, "incidents": [] }"#
        #expect(try StatusClient.parse(Data(json.utf8)).hasProblem == false)
    }

    @Test func newIncidentsOnlyAfterFirstFetch() throws {
        let status = try StatusClient.parse(Data(sample.utf8))
        #expect(StatusClient.newIncidents(from: nil, to: status).isEmpty)
        let calm = ServiceStatus(level: .operational, summary: "")
        #expect(StatusClient.newIncidents(from: calm, to: status).map(\.id) == ["a1"])
        #expect(StatusClient.newIncidents(from: status, to: status).isEmpty)
    }
}
