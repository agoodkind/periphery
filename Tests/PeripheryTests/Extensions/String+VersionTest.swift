import Foundation
import XCTest

final class StringVersionTest: XCTestCase {
    func testForkReleaseComparison() {
        XCTAssertTrue("3.8.0-agoodkind.10".isReleaseNewer(than: "3.8.0-agoodkind.2"))
        XCTAssertFalse("3.8.0-agoodkind.2".isReleaseNewer(than: "3.8.0-agoodkind.10"))
        XCTAssertTrue("3.9.0-agoodkind.1".isReleaseNewer(than: "3.8.0-agoodkind.10"))
        XCTAssertFalse("3.8.0-agoodkind.2".isReleaseNewer(than: "3.8.0-agoodkind.2"))
        XCTAssertFalse("3.8.0-agoodkind.2".isReleaseNewer(than: "development"))
    }

    func testVersion() {
        XCTAssertTrue("9.3".isVersion(lessThan: "10.0"))
        XCTAssertTrue("9.3.1".isVersion(lessThan: "10.0"))
        XCTAssertTrue("9.3.1".isVersion(lessThan: "9.3.2"))
        XCTAssertTrue("9.3.3".isVersion(greaterThan: "9.3.2"))

        XCTAssertFalse("9.3.1".isVersion(equalTo: "9.3"))
        XCTAssertFalse("9.3".isVersion(equalTo: "10.0"))
    }
}
