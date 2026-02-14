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

    func testExample() async throws {
        let heartBeat = HeartBeat(send: 20_000, recv: 0)
        let stomp = ZenSTOMP(
            eventLoopGroup: eventLoopGroup,
            host: "kangaroo.rmq.cloudamqp.com",
            port: 61613,
            heartBeat: heartBeat
        )
        stomp.virtualHost = "oifmfdep"
        stomp.onMessageReceived = { message in
            print(String(data: message.body, encoding: .utf8) ?? "")
        }
        stomp.onHandlerRemoved = {
            print("Handler removed")
        }
        stomp.onErrorCaught = { error in
            print("error: \(error)")
        }

        try await stomp.connect(username: "oifmfdep", password: "dseFl8Mrz61r3ExAeBgowV-vnHEh05GW")
        let destination = ".commands"
        try await stomp.subscribe(id: "1", destination: destination, ack: .auto)

        Task {
            for i in 0..<5 {
                try await stomp.send(destination: destination, payload: "Test message \(i)".data(using: .utf8)!)
            }
        }
        
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        try await stomp.disconnect()
    }

    func testExampleTLS() async throws {
        let heartBeat = HeartBeat(send: 20_000, recv: 0)
        let stomp = ZenSTOMP(
            eventLoopGroup: eventLoopGroup,
            host: "kangaroo.rmq.cloudamqp.com",
            port: 61614,
            heartBeat: heartBeat
        )
        try stomp.enableTLS()
        stomp.virtualHost = "oifmfdep"

        try await stomp.connect(username: "oifmfdep", password: "dseFl8Mrz61r3ExAeBgowV-vnHEh05GW")
        try await stomp.disconnect()
    }

    func parse(buffer: Data) -> STOMPFrame? {
        var index = 0
        let count = buffer.count
        for i in 0..<count {
            if i > 5 && buffer[i..<(i + 2)] == Data([0x0a, 0x0a]) {
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

    func testDecoderParsesFrameWithContentLength() throws {
        let decoder = STOMPFrameDecoder()
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("MESSAGE\ncontent-length:5\ncustom:a:b\n\nhello\0")

        let frame = try decoder.parse(buffer: &buffer)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.head.command, .MESSAGE)
        XCTAssertEqual(frame?.head.headers["custom"], "a:b")
        XCTAssertEqual(String(data: frame?.body ?? Data(), encoding: .utf8), "hello")
    }

    func testDecoderReturnsNilOnIncompleteFrame() throws {
        let decoder = STOMPFrameDecoder()
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("MESSAGE\ncontent-length:5\n\nhel")

        let originalReader = buffer.readerIndex
        let frame = try decoder.parse(buffer: &buffer)
        XCTAssertNil(frame)
        XCTAssertEqual(buffer.readerIndex, originalReader)
    }

    func testDecoderThrowsOnInvalidContentLength() {
        let decoder = STOMPFrameDecoder()
        var buffer = ByteBufferAllocator().buffer(capacity: 0)
        buffer.writeString("MESSAGE\ncontent-length:abc\n\nhello\0")

        XCTAssertThrowsError(try decoder.parse(buffer: &buffer)) { error in
            guard case STOMPFrameDecoderError.invalidContentLength("abc") = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }
}
