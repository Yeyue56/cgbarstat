import XCTest
@testable import StipendCore

final class PackageSmokeTests: XCTestCase {
    func testProductName() {
        XCTAssertEqual(StipendCoreMarker.productName, "Stipend")
    }
}
