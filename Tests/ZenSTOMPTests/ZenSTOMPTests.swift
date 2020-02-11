import XCTest
import NIO
@testable import ZenSTOMP

final class ZenSTOMPTests: XCTestCase {
    var eventLoopGroup: MultiThreadedEventLoopGroup!
    
    override func setUp() {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    override func tearDown() {
        try! eventLoopGroup.syncShutdownGracefully()
    }

    func testExample() {
        let stomp = ZenSTOMP(host: "stomp.server.org", port: 61716, autoreconnect: true, eventLoopGroup: eventLoopGroup)
        XCTAssertNoThrow(try stomp.addTLS(cert: "certificate.crt", key: "private.key"))
        stomp.addKeepAlive(seconds: 30, destination: "/alive", message: "IoT Gateway is alive")
        stomp.onMessageReceived = { message in
            print(String(data: message.body, encoding: .utf8)!)
        }
        stomp.onHandlerRemoved = {
            print("Handler removed")
        }
        stomp.onErrorCaught = { error in
            print(error.localizedDescription)
        }
        
        do {
            let destination = "test.123456.commands"
            
            try stomp.connect(username: "test", password: "test").wait()
            try stomp.subscribe(id: "1", destination: destination, ack: .client).wait()
            sleep(3)

            try stomp.send(destination: destination, payload: "Test message 1 start".data(using: .utf8)!).wait()
            sleep(5)

            try stomp.send(destination: destination, payload: "Test message 2 continue".data(using: .utf8)!).wait()
            sleep(5)

            try stomp.send(destination: destination, payload: "Test message 3 continue".data(using: .utf8)!).wait()
            sleep(50)
            try stomp.send(destination: destination, payload: "Test message 4 end".data(using: .utf8)!).wait()
            sleep(5)

            try stomp.unsubscribe(id: "1").wait()
            try stomp.disconnect().wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
