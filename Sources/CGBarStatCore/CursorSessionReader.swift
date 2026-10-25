import Foundation

public enum CursorPaths {
    public static var stateDatabase: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }
}

public enum SessionReadResult: Equatable, Sendable {
    case token(String)
    case notSignedIn
    /// Cursor 3.27 起把令牌加密写入数据库。钥匙串口令读不到时不能把密文当成登录。
    case sealed
}

public enum SessionError: Error, Equatable {
    case unreadable
}

public enum CursorToken {
    /// 保存的值有时是 `前缀:类型:载荷`。载荷本身或它的 Base64 是 JWT 时，请求用量用这一段。
    /// 解不开就用原值。调用方不要把解开的结果写回 Cursor 的数据库。
    public static func sessionToken(from stored: String) -> String {
        if isJWT(stored) { return stored }
        let parts = stored.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return stored }
        let tail = String(parts[2])
        if isJWT(tail) { return tail }
        guard let data = decodeBase64(tail),
              let text = String(data: data, encoding: .utf8) else {
            return stored
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isJWT(trimmed) ? trimmed : stored
    }

    private static func isJWT(_ value: String) -> Bool {
        guard value.hasPrefix("eyJ") else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty }
    }

    private static func decodeBase64(_ value: String) -> Data? {
        var text = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder > 0 {
            text.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: text)
    }
}

enum TokenText {
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.first == "\"",
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            let token = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        }
        return trimmed
    }
}

public struct CursorSessionReader: Sendable {
    public var databasePath: String
    public var openSealed: @Sendable (String) -> String?

    public init(
        databasePath: String = CursorPaths.stateDatabase,
        openSealed: (@Sendable (String) -> String?)? = nil
    ) {
        self.databasePath = databasePath
        self.openSealed = openSealed ?? { CursorSafeStorage.open($0) }
    }

    /// 只读查询 access token。文件不存在视为未登录。进程失败视为不可读。
    public func read() throws -> SessionReadResult {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            return .notSignedIn
        }
        let output: String
        do {
            output = try SQLite3CLI.query(
                databasePath: databasePath,
                sql: "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
            )
        } catch {
            throw SessionError.unreadable
        }
        guard let token = TokenText.normalize(output) else {
            return .notSignedIn
        }
        return opened(token)
    }

    /// 仪表盘会话需要的用户标识。没有该键时返回 nil。
    public func readSessionUserId() throws -> String? {
        try readOptionalItem("cursorAuth/stripeMembershipAuthId")
    }

    /// 没有 refresh token 时返回 nil。数据库打不开时抛出，避免把读失败当成未登录。
    public func readRefreshToken() throws -> String? {
        guard FileManager.default.fileExists(atPath: databasePath) else { return nil }
        let output: String
        do {
            output = try SQLite3CLI.query(
                databasePath: databasePath,
                sql: "SELECT value FROM ItemTable WHERE key = 'cursorAuth/refreshToken' LIMIT 1;"
            )
        } catch {
            throw SessionError.unreadable
        }
        guard let token = TokenText.normalize(output) else { return nil }
        if case .token(let opened) = opened(token) { return opened }
        return nil
    }

    private func opened(_ stored: String) -> SessionReadResult {
        guard CursorSafeStorage.isSealed(stored) else { return .token(stored) }
        guard let token = openSealed(stored) else { return .sealed }
        return .token(token)
    }

    private func readOptionalItem(_ key: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: databasePath) else { return nil }
        let escaped = key.replacingOccurrences(of: "'", with: "''")
        let output: String
        do {
            output = try SQLite3CLI.query(
                databasePath: databasePath,
                sql: "SELECT value FROM ItemTable WHERE key = '\(escaped)' LIMIT 1;"
            )
        } catch {
            throw SessionError.unreadable
        }
        return TokenText.normalize(output)
    }

    /// 把新令牌写回 Cursor 原来的 ItemTable。不写快照、日志或仓库。
    /// access token 被拒绝后必须换新并落盘，否则下一次启动仍会用失效的令牌。
    public func updateTokens(accessToken: String, refreshToken: String?) throws {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw SessionError.unreadable
        }
        try writeToken(key: "cursorAuth/accessToken", token: accessToken)
        if let refreshToken, !refreshToken.isEmpty {
            try writeToken(key: "cursorAuth/refreshToken", token: refreshToken)
        }
    }

    private func writeToken(key: String, token: String) throws {
        let existing = try? SQLite3CLI.query(
            databasePath: databasePath,
            sql: "SELECT value FROM ItemTable WHERE key = '\(key.replacingOccurrences(of: "'", with: "''"))' LIMIT 1;"
        )
        let stored = existing?.trimmingCharacters(in: .newlines) ?? ""
        let persisted: String
        if stored.first == "\"" {
            persisted = String(decoding: try JSONEncoder().encode(token), as: UTF8.self)
        } else {
            persisted = token
        }
        let hex = persisted.utf8.map { String(format: "%02x", $0) }.joined()
        let keySQL = key.replacingOccurrences(of: "'", with: "''")
        // key 是 TEXT。用 blob 字面量和它比较不会命中，所以键用文本，值用十六进制，避免令牌里的引号打断 SQL。
        do {
            try SQLite3CLI.execute(
                databasePath: databasePath,
                sql: """
                PRAGMA busy_timeout=3000;
                UPDATE ItemTable SET value = x'\(hex)' WHERE key = '\(keySQL)';
                INSERT INTO ItemTable(key, value)
                SELECT '\(keySQL)', x'\(hex)'
                WHERE NOT EXISTS (SELECT 1 FROM ItemTable WHERE key = '\(keySQL)');
                """
            )
        } catch {
            throw SessionError.unreadable
        }
    }
}

enum SQLite3CLI {
    /// 标准输出需能放进管道缓冲区。这里只读取一条短令牌。
    static func query(databasePath: String, sql: String) throws -> String {
        let encoded = databasePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? databasePath
        return try run(arguments: ["file:\(encoded)?mode=ro", sql])
    }

    static func execute(databasePath: String, sql: String) throws {
        _ = try run(arguments: [databasePath, sql])
    }

    private static func run(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SessionError.unreadable
        }
        return output
    }
}
