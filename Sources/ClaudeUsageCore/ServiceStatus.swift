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

    /// 이전 상태에는 없던 새 장애. 앱을 켤 때마다 진행 중인 장애로 알림이 오지 않도록 첫 조회(old == nil)에서는 비웁니다.
    public static func newIncidents(from old: ServiceStatus?, to new: ServiceStatus) -> [ServiceStatus.Incident] {
        guard let old else { return [] }
        let known = Set(old.incidents.map(\.id))
        return new.incidents.filter { !known.contains($0.id) }
    }
}
