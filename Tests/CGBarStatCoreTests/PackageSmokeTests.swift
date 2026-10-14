import XCTest
@testable import CGBarStatCore

final class PackageSmokeTests: XCTestCase {
    func testProductName() {
        XCTAssertEqual(CGBarStatCoreMarker.productName, "CGBarStat")
    }
}
