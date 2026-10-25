import Foundation

/// Claude 서비스 상태 (https://status.claude.com, Atlassian Statuspage 공개 API).
/// 인증이 필요 없고 계정 정보도 보내지 않습니다.
public struct ServiceStatus: Equatable, Sendable {
    public enum Level: String, Sendable {
        case operational = "none"
        case minor, major, critical, maintenance
    }

    public struct Incident: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var url: URL?

        public init(id: String, name: String, url: URL? = nil) {
            self.id = id
            self.name = name
            self.url = url
        }
    }

    public var level: Level
    /// 상태 페이지가 정한 한 줄 요약 (예: "Partially Degraded Service")
    public var summary: String
    public var incidents: [Incident]

    public init(level: Level, summary: String, incidents: [Incident] = []) {
        self.level = level
        self.summary = summary
        self.incidents = incidents
    }

    public var hasProblem: Bool {
        level != .operational || !incidents.isEmpty
    }

    public static let pageURL = URL(string: "https://status.claude.com")!
}

public struct StatusClient: Sendable {
    public static let endpoint = URL(string: "https://status.claude.com/api/v2/summary.json")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch() async throws -> ServiceStatus {
        let request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> ServiceStatus {
        struct Summary: Decodable {
            struct Status: Decodable {
                var indicator: String?
                var description: String?
            }

            struct Incident: Decodable {
                var id: String
                var name: String
                var status: String?
                var shortlink: String?
            }

            var status: Status?
            var incidents: [Incident]?
        }

        guard let summary = try? JSONDecoder().decode(Summary.self, from: data) else {
            throw UsageError.decoding
        }
        let level = summary.status?.indicator.flatMap(ServiceStatus.Level.init(rawValue:)) ?? .operational
        let incidents = (summary.incidents ?? [])
            .filter { $0.status != "resolved" && $0.status != "postmortem" }
            .map { ServiceStatus.Incident(id: $0.id, name: $0.name, url: $0.shortlink.flatMap(URL.init(string:))) }
        return ServiceStatus(level: level, summary: summary.status?.description ?? "", incidents: incidents)
    }

}

/// 어떤 장애를 이미 알렸는지 기억해서, 장애마다 "발생"과 "복구" 알림을 한 번씩만 보내게 합니다.
/// 기억한 ID는 앱을 다시 켜도 유지되므로(UserDefaults), 켤 때마다 같은 알림이 오지 않습니다.
public struct IncidentTracker: Equatable, Sendable {
    /// 발생을 알린, 아직 복구되지 않은 장애 (ID → 이름)
    public private(set) var active: [String: String]

    public init(active: [String: String] = [:]) {
        self.active = active
    }

    public struct Changes: Equatable, Sendable {
        public var started: [ServiceStatus.Incident]
        public var resolved: [String]
    }

    /// 새 상태를 반영하고 알려야 할 변화(새 장애, 복구된 장애 이름)를 돌려줍니다.
    public mutating func update(with status: ServiceStatus) -> Changes {
        let current = Dictionary(status.incidents.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let started = status.incidents.filter { active[$0.id] == nil }
        let resolved = active.filter { current[$0.key] == nil }.map(\.value).sorted()
        active = current
        return Changes(started: started, resolved: resolved)
    }
}
