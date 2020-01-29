import XCTest
import NIO
@testable import ZenSTOMP

final class ZenSTOMPTests: XCTestCase {
    func testExample() {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        let stomp = ZenSTOMP(host: "server.stomp.org", port: 61716, eventLoopGroup: eventLoopGroup)
        stomp.onMessage = { message in
            debugPrint("MESSAGE: \(message.head)")
        }
        
        do {
            try stomp.start().wait()

            try stomp.connect(username: "admin", password: "admin").wait()
            sleep(1)

            /// SUBSCRIBE
            try stomp.subscribe(id: "1", destination: "/topic/test").wait()
            sleep(5)
            try stomp.unsubscribe(id: "1").wait()

            /// SEND
            try stomp.send(destination: "/topic/test/send", payload: "IoT Gateway is alive".data(using: .utf8)!).wait()
            sleep(3)

            try stomp.disconnect().wait()
            try stomp.stop().wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
