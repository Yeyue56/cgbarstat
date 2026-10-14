import XCTest
@testable import StipendCore

final class SnapshotStoreTests: XCTestCase {
    func testRoundTripMarksLoadedSnapshotStale() throws {
        let suite = "stipend.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = UserDefaultsSnapshotStore(defaults: defaults)
        let snapshot = UsageSnapshot(
            cursorModels: ModelPool(percent: 62, periodTokens: 1000, todayTokens: 100, models: []),
            otherModels: ModelPool.empty,
            grokBot: GrokBotUsage(allowance: .included, percent: 46, resetAt: nil),
            fetchedAt: Date(timeIntervalSince1970: 10),
            cursorStale: false,
            grokStale: false
        )
        store.save(snapshot)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.cursorModels.percent, 62)
        XCTAssertEqual(loaded.grokBot.percent, 46)
        XCTAssertTrue(loaded.cursorStale)
        XCTAssertTrue(loaded.grokStale)
        let data = try XCTUnwrap(defaults.data(forKey: UserDefaultsSnapshotStore.key))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("token"))
        XCTAssertFalse(text.contains("Bearer"))
    }
}
