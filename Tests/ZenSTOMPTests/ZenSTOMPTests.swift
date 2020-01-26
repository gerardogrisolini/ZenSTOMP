import XCTest
@testable import ZenSTOMP

final class ZenSTOMPTests: XCTestCase {
    func testExample() {
        let stomp = ZenSTOMP(host: "localhost", port: 61716)
        XCTAssertNoThrow(try stomp.start().wait())
        stomp.stop()
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
