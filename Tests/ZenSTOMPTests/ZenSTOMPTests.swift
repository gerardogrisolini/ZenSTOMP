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
        let deviceType = "VIET_DEVICE"
        let deviceId = "1000037040"
        
        let stomp = ZenSTOMP(host: "biesseprodnf-gwagent.cpaas-accenture.com", port: 61716, reconnect: true, eventLoopGroup: eventLoopGroup)
        XCTAssertNoThrow(try stomp.addTLS(
            cert: "/Users/gerardo/Projects/opcua/opcua/Assets/stunnel_client_neptune.pem.crt",
            key: "/Users/gerardo/Projects/opcua/opcua/Assets/stunnel_client.private_neptune.pem.key"
        ))
        stomp.addKeepAlive(seconds: 15, destination: "/topic/biesse/\(deviceType).\(deviceId).alive", message: "IoT Gateway is alive")
        stomp.onMessageReceived = { message in
            print(String(data: message.body, encoding: .utf8)!)
        }
        stomp.onHandlerRemoved = {
            print("Handler removed")
        }
        stomp.onErrorCaught = { error in
            print("error: \(error.localizedDescription)")
        }
        
        do {
            let destination = ".biesse.\(deviceType).\(deviceId).commands"
            
            try stomp.connect(username: "admin", password: "Accenture.123!").wait()
            try stomp.subscribe(id: "1", destination: destination, ack: .auto).wait()

//            DispatchQueue.global(qos: .utility).async {
//                sleep(2)
//                //do {
//                    for i in 0..<5 {
//                        stomp.send(destination: destination, payload: "Test message \(i)".data(using: .utf8)!).whenComplete { _ in }
//                    }
//                //} catch {
//                //    XCTFail(error.localizedDescription)
//                //}
//            }

            sleep(20)

            try stomp.unsubscribe(id: "1").wait()
            try stomp.disconnect().wait()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    
    func parse(buffer: Data) -> STOMPFrame? {
        var index = 0
        let count = buffer.count
        for i in 0..<count {
            if i > 5 && buffer[i..<(i+2)] == Data([0x0a,0x0a]) {
                index = i + 2
                break
            }
        }
        
        if let string = String(data: buffer[0...index], encoding: .utf8) {
            let bytes = buffer[index...(count - 2)]
            
            var head = STOMPFrameHead()
            let rows = string.split(separator: "\n", omittingEmptySubsequences: true)
            for row in rows {
                if row.contains(":") {
                    let cols = row.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: true)
                    let key = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    head.headers[key] = value
                } else if let command = Command(rawValue: row.description) {
                    head.command = command
                }
            }
            
            return STOMPFrame(head: head, body: Data(bytes))
        }
        
        return nil
    }
    
    func testParse() {
        let buffer = """
\n\n\nMESSAGE\nexpires:0\ndestination:/queue/.biesse.VIET_DEVICE.1000035065.commands\nsubscription:2\npriority:4\nbreadcrumbId:ID-localhost-32979-1581319115552-58-7993\nmessage-id:ID\\clocalhost-42526-1581319117547-69\\c3251\\c1\\c1\\c1\npersistent:true\ntimestamp:1581608995285\n\nIS CONFIG|ew0KICAiY21kIjogInVwbG9hZEJpZXNzZUxvZ0ZpbGUiDQp9\0\n
""".data(using: .utf8)!
        
        _ = parse(buffer: buffer)
    }


    static var allTests = [
        ("testExample", testExample),
        ("testParse", testParse),
    ]
}
