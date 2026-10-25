import XCTest
@testable import CGBarStatCore

final class CursorSessionReaderTests: XCTestCase {
    func testSafeStorageRoundTripMatchesChromiumV10() {
        let sealed = "cursor-safe-storage:v1:djEwWYhmSnp1q+qiTrBMIfHTGqxKxLmInuo8HX2UP86Z4BiIQadRbuQ680bP9VNiVxNHjA4ytuvGrbXz3Gw+8zuoOQ=="
        let jwt = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1c2VyX3Rlc3QifQ.c2ln"
        XCTAssertEqual(CursorSafeStorage.open(sealed, password: "test-password"), jwt)
        XCTAssertEqual(CursorSafeStorage.seal(jwt, password: "test-password"), sealed)
        XCTAssertNil(CursorSafeStorage.open(sealed, password: "wrong-password"))
    }

    func testSealedDatabaseTokenUsesKeychainOpener() throws {
        let sealed = "cursor-safe-storage:v1:abc"
        let path = try makeDatabase(valueSQL: "'\(sealed)'")
        let opened = CursorSessionReader(databasePath: path) { stored in
            XCTAssertEqual(stored, sealed)
            return "opened-token"
        }
        XCTAssertEqual(try opened.read(), .token("opened-token"))
        let locked = CursorSessionReader(databasePath: path) { _ in nil }
        XCTAssertEqual(try locked.read(), .sealed)
    }

    func testSessionTokenUsesJWTAfterSecondColon() {
        let jwt = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ1c2VyX3Rlc3QifQ.c2ln"
        let encoded = Data(jwt.utf8).base64EncodedString()
        XCTAssertEqual(CursorToken.sessionToken(from: "0123456789012345678:ab:\(encoded)"), jwt)
        XCTAssertEqual(CursorToken.sessionToken(from: "aa:bb:\(jwt)"), jwt)
        XCTAssertEqual(CursorToken.sessionToken(from: jwt), jwt)
        XCTAssertEqual(CursorToken.sessionToken(from: "plain-token"), "plain-token")
        XCTAssertEqual(CursorToken.sessionToken(from: "aa:bb:not-jwt"), "aa:bb:not-jwt")
    }

    func testNormalizesPlainAndJSONStringValues() {
        XCTAssertEqual(TokenText.normalize("  abc  \n"), "abc")
        XCTAssertEqual(TokenText.normalize("\"abc\""), "abc")
        XCTAssertNil(TokenText.normalize("   "))
        XCTAssertNil(TokenText.normalize("\"\""))
    }

    func testReadsTokenFromReadOnlyDatabase() throws {
        let path = try makeDatabase(valueSQL: "'test-token'")
        XCTAssertEqual(try CursorSessionReader(databasePath: path).read(), .token("test-token"))
    }

    func testReadsJSONEncodedToken() throws {
        let path = try makeDatabase(valueSQL: "'\"json-token\"'")
        XCTAssertEqual(try CursorSessionReader(databasePath: path).read(), .token("json-token"))
    }

    func testMissingFileIsSignedOut() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("state.vscdb").path
        XCTAssertEqual(try CursorSessionReader(databasePath: path).read(), .notSignedIn)
    }

    func testEmptyValueIsSignedOut() throws {
        let path = try makeDatabase(valueSQL: "''")
        XCTAssertEqual(try CursorSessionReader(databasePath: path).read(), .notSignedIn)
    }

    func testUpdateTokensRoundTripKeepsQuotedStorage() throws {
        let path = try makeDatabase(valueSQL: "'\"old-access\"'")
        try SQLite3CLI.execute(
            databasePath: path,
            sql: "INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/refreshToken', '\"old-refresh\"');"
        )
        let reader = CursorSessionReader(databasePath: path)
        try reader.updateTokens(accessToken: "next'access", refreshToken: "next-refresh")
        XCTAssertEqual(try reader.read(), .token("next'access"))
        XCTAssertEqual(try reader.readRefreshToken(), "next-refresh")
        let stored = try SQLite3CLI.query(
            databasePath: path,
            sql: "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1;"
        )
        XCTAssertTrue(stored.contains("\"next'access\""))
    }

    func testUpdateTokensOnBlobColumn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("state.vscdb").path
        try SQLite3CLI.execute(
            databasePath: path,
            sql: """
            CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
            INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', 'old-access');
            INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/refreshToken', 'old-refresh');
            """
        )
        let reader = CursorSessionReader(databasePath: path)
        try reader.updateTokens(accessToken: "new-access", refreshToken: "new-refresh")
        XCTAssertEqual(try reader.read(), .token("new-access"))
        XCTAssertEqual(try reader.readRefreshToken(), "new-refresh")
    }

    private func makeDatabase(valueSQL: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("state.vscdb").path
        try SQLite3CLI.execute(
            databasePath: path,
            sql: "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT); INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', \(valueSQL));"
        )
        return path
    }
}
