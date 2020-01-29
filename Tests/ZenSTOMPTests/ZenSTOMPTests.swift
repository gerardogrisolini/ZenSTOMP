import XCTest
@testable import ZenSTOMP

final class ZenSTOMPTests: XCTestCase {
    func testExample() {
        let stomp = ZenSTOMP(host: "server.stomp.org", port: 61716)
        stomp.onResponse = { response in
            debugPrint("RESPONSE: \(response.head)")
        }
        XCTAssertNoThrow(try stomp.start().wait())

        stomp.connect(username: "admin", password: "admin")
        sleep(1)

        /// SUBSCRIBE
        stomp.subscribe(id: "1", destination: "/topic/test)
        sleep(5)
        stomp.unsubscribe(id: "1")

        /// SEND
        stomp.send(destination: "/topic/test/send", payload: "IoT Gateway is alive".data(using: .utf8)!)
        sleep(3)

        stomp.disconnect()
        stomp.stop()
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
