import XCTest
@testable import CGBarStatCore

final class CursorSessionReaderTests: XCTestCase {
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
