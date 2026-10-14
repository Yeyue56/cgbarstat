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
}

public enum SessionError: Error, Equatable {
    case unreadable
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

    public init(databasePath: String = CursorPaths.stateDatabase) {
        self.databasePath = databasePath
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
        return .token(token)
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
