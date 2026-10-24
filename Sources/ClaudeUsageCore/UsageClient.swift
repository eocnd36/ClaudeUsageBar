import Foundation

public enum UsageError: Error, Equatable, Sendable {
    /// Claude Code 로그인 정보를 찾지 못함
    case notLoggedIn
    /// 토큰 만료 또는 권한 없음 (401/403)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case network(String)
    case server(Int)
    case decoding
}

/// 연결된 Claude 계정 정보 (GET /api/oauth/profile)
public struct AccountProfile: Decodable, Equatable, Sendable {
    public var email: String?
    public var displayName: String?
    public var organizationName: String?

    public init(email: String? = nil, displayName: String? = nil, organizationName: String? = nil) {
        self.email = email
        self.displayName = displayName
        self.organizationName = organizationName
    }

    private struct Account: Decodable {
        var email: String?
        var displayName: String?
        var fullName: String?

        enum CodingKeys: String, CodingKey {
            case email
            case displayName = "display_name"
            case fullName = "full_name"
        }
    }

    private struct Organization: Decodable {
        var name: String?
    }

    enum CodingKeys: String, CodingKey {
        case account, organization
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let account = try? c.decodeIfPresent(Account.self, forKey: .account)
        let organization = try? c.decodeIfPresent(Organization.self, forKey: .organization)
        email = account?.email
        displayName = account?.displayName ?? account?.fullName
        organizationName = organization?.name
    }
}

public struct UsageClient: Sendable {
    public static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    private let session: URLSession
    private let userAgent: String
    private let languages: [String]

    /// - Parameter languages: 서버가 돌려주는 표시 이름(예: 사용처 이름)의 언어. 앱 언어를 넘겨 주세요.
    public init(session: URLSession = .shared, userAgent: String = "ClaudeUsageBar", languages: [String] = []) {
        self.session = session
        self.userAgent = userAgent
        self.languages = languages
    }

    public func fetch(token: String) async throws -> UsageResponse {
        try await get(Self.usageEndpoint, token: token)
    }

    public func fetchProfile(token: String) async throws -> AccountProfile {
        try await get(Self.profileEndpoint, token: token)
    }

    /// `["ko", "en"]` → `ko, en;q=0.9`
    static func acceptLanguage(_ languages: [String]) -> String? {
        guard !languages.isEmpty else { return nil }
        return languages.prefix(5).enumerated().map { index, language in
            index == 0 ? language : "\(language);q=\(String(format: "%.1f", 1 - Double(index) * 0.1))"
        }.joined(separator: ", ")
    }

    private func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let acceptLanguage = Self.acceptLanguage(languages) {
            request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw UsageError.decoding }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw UsageError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageError.rateLimited(retryAfter: retryAfter)
        default:
            throw UsageError.server(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw UsageError.decoding
        }
    }
}
