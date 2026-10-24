import Foundation

/// Claude Code가 로그인할 때 저장하는 OAuth 정보.
///
/// 이 앱은 토큰을 읽기만 하고 절대 갱신하거나 다시 쓰지 않습니다.
/// (리프레시 토큰을 대신 쓰면 Claude Code 쪽 로그인이 깨질 수 있기 때문)
/// 토큰이 만료되면 사용자가 `claude`를 한 번 실행하면 Claude Code가 갱신합니다.
public struct ClaudeCredentials: Equatable, Sendable {
    public var accessToken: String
    public var expiresAt: Date?
    public var subscriptionType: String?
    public var rateLimitTier: String?

    public init(accessToken: String, expiresAt: Date? = nil, subscriptionType: String? = nil, rateLimitTier: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    /// "Pro", "Max 5x", "Max 20x" 같은 표시용 플랜 이름
    public var planName: String? {
        if let tier = rateLimitTier?.lowercased() {
            if tier.contains("max_20x") { return "Max 20x" }
            if tier.contains("max_5x") { return "Max 5x" }
        }
        guard let type = subscriptionType, !type.isEmpty else { return nil }
        return type.prefix(1).uppercased() + type.dropFirst()
    }

    public static func parse(_ data: Data) throws -> ClaudeCredentials {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw CredentialError.malformed
        }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000)
        }
        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        )
    }
}

public enum CredentialError: Error, Equatable {
    case notFound
    case malformed
}

/// macOS 키체인(`Claude Code-credentials`) → `~/.claude/.credentials.json` 순서로 찾습니다.
public struct CredentialLoader: Sendable {
    public static let keychainService = "Claude Code-credentials"

    private let environment: [String: String]
    private let home: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.home = home
    }

    public func load() throws -> ClaudeCredentials {
        if let data = readKeychain(), let credentials = try? ClaudeCredentials.parse(data) {
            return credentials
        }
        for url in credentialFiles {
            if let data = try? Data(contentsOf: url), let credentials = try? ClaudeCredentials.parse(data) {
                return credentials
            }
        }
        throw CredentialError.notFound
    }

    var credentialFiles: [URL] {
        var dirs: [URL] = []
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            dirs.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath))
        }
        dirs.append(home.appendingPathComponent(".claude"))
        return dirs.map { $0.appendingPathComponent(".credentials.json") }
    }

    /// 키체인 항목은 Claude Code가 `/usr/bin/security`로 만들기 때문에
    /// 같은 도구로 읽으면 별도의 키체인 접근 허용 팝업이 뜨지 않습니다.
    private func readKeychain() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", Self.keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Data(trimmed.utf8)
    }
}
