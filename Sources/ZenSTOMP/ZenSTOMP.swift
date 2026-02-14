//
//  ZenSTOMP.swift
//
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
@preconcurrency import NIO
@preconcurrency import NIOSSL

public struct HeartBeat: Sendable {
    let send: Int
    let recv: Int
    var string: String { "\(send),\(recv)" }

    public init(send: Int = 0, recv: Int = 0) {
        self.send = send
        self.recv = recv
    }
}

enum STOMPError: Error {
    case connectionError
    case alreadyConnecting
    case connectionClosed
    case connectionTimeout
    case serverError(String)
}

public final class ZenSTOMP: @unchecked Sendable {
    private let host: String
    private let port: Int
    private let eventLoopGroup: EventLoopGroup
    private var channel: Channel? = nil
    private var sslContext: NIOSSLContext? = nil
    private let handler = STOMPHandler()
    private var repeatedTask: RepeatedTask? = nil
    private let connectResponseTimeoutNanoseconds: UInt64 = 10_000_000_000
    private let connectWaiterLock = NSLock()
    private var connectWaiter: CheckedContinuation<Void, Error>?

    private var username: String?
    private var password: String?
    private var receipt: String?
    private var topics = [String: Topic]()
    private var autoreconnect: Bool = false
    private var keepAlive: Int64 = 0
    private var destination: String = "*"
    private var message: String? = nil
    public var version: String = "1.2"
    public var virtualHost: String? = nil
    public let heartBeat: HeartBeat

    public var onMessageReceived: STOMPMessageReceived? = nil
    public var onHandlerRemoved: STOMPHandlerRemoved? = nil
    public var onErrorCaught: STOMPErrorCaught? = nil

    public init(eventLoopGroup: EventLoopGroup, host: String, port: Int, heartBeat: HeartBeat = HeartBeat(), reconnect: Bool = true) {
        self.host = host
        self.port = port
        self.heartBeat = heartBeat
        self.autoreconnect = reconnect
        self.eventLoopGroup = eventLoopGroup
    }

    public func addTLS(cert: String, key: String) throws {
        let certs = try NIOSSLCertificate.fromPEMFile(cert)
        let privateKey = try NIOSSLPrivateKey(file: key, format: .pem)

        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = .none
        config.certificateChain = certs.map { .certificate($0) }
        config.privateKey = .privateKey(privateKey)

        sslContext = try NIOSSLContext(configuration: config)
    }

    public func enableTLS(certificateVerification: CertificateVerification = .fullVerification) throws {
        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = certificateVerification
        sslContext = try NIOSSLContext(configuration: config)
    }

    private func start() async throws {
        let host = self.host
        let port = self.port
        let sslContext = self.sslContext
        let stompHandler = self.handler

        let channel = try await ClientBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
            .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .channelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .channelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            .channelOption(ChannelOptions.connectTimeout, value: TimeAmount.seconds(8))
            .channelInitializer { channel in
                do {
                    if let sslContext {
                        let sslClientHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                        try channel.pipeline.syncOperations.addHandler(sslClientHandler)
                    }
                    try channel.pipeline.syncOperations.addHandler(MessageToByteHandler(STOMPFrameEncoder()))
                    try channel.pipeline.syncOperations.addHandler(ByteToMessageHandler(STOMPFrameDecoder()))
                    try channel.pipeline.syncOperations.addHandler(stompHandler)
                    return channel.eventLoop.makeSucceededFuture(())
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .connect(host: host, port: port)
            .get()

        self.channel = channel
    }

    private func stop() async throws {
        repeatedTask?.cancel()
        repeatedTask = nil
        resumeConnectWaiter(.failure(STOMPError.connectionClosed))

        guard let channel else {
            throw STOMPError.connectionError
        }

        channel.flush()
        try await channel.close(mode: .all).get()
        self.channel = nil
    }

    private func send(frame: STOMPFrame) async throws {
        guard let channel else {
            throw STOMPError.connectionError
        }

        try await channel.writeAndFlush(frame).get()
    }

    private func startKeepAlive() {
        repeatedTask?.cancel()

        guard let channel, keepAlive > 0 else { return }

        var headers = [String: String]()
        headers["destination"] = destination

        var frame = STOMPFrame(head: STOMPFrameHead(command: .SEND, headers: headers))
        if let body = message?.data(using: .utf8) {
            frame.body = body
        }
        let keepAliveFrame = frame

        let time = TimeAmount.seconds(keepAlive)
        repeatedTask = channel.eventLoop.scheduleRepeatedTask(initialDelay: time, delay: time) { _ in
            Task { [weak self] in
                guard let self else { return }
                try? await self.send(frame: keepAliveFrame)
            }
        }
    }

    public func addKeepAlive(seconds: Int64, destination: String = "*", message: String? = nil) {
        keepAlive = seconds
        self.destination = destination
        self.message = message
    }

    public func reconnect(subscribe: Bool) async throws {
        try await start()

        var headers = [String: String]()
        headers["accept-version"] = version
        headers["host"] = virtualHost ?? host
        headers["heart-beat"] = heartBeat.string
        headers["login"] = username
        headers["passcode"] = password
        if let receipt {
            headers["receipt"] = receipt
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .CONNECT, headers: headers))
        try await sendConnectAndWaitConnected(frame: frame)

        if subscribe {
            await resubscribe()
        }
        startKeepAlive()
    }

    public func connect(username: String, password: String, receipt: String? = nil) async throws {
        self.username = username
        self.password = password
        self.receipt = receipt

        handler.messageReceived = onMessageReceived
        handler.errorCaught = onErrorCaught
        handler.connected = { [weak self] _ in
            self?.resumeConnectWaiter(.success(()))
        }
        handler.serverError = { [weak self] frame in
            let message = frame.head.headers["message"] ?? String(data: frame.body, encoding: .utf8) ?? "STOMP ERROR"
            self?.resumeConnectWaiter(.failure(STOMPError.serverError(message)))
        }
        handler.handlerRemoved = { [weak self] in
            guard let self else { return }

            self.resumeConnectWaiter(.failure(STOMPError.connectionClosed))
            self.onHandlerRemoved?()

            if self.autoreconnect {
                Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    try? await self.reconnect(subscribe: true)
                }
            }
        }

        try await reconnect(subscribe: false)
    }

    public func disconnect(receipt: String? = nil) async throws {
        autoreconnect = false

        var headers = [String: String]()
        if let receipt {
            headers["receipt"] = receipt
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .DISCONNECT, headers: headers))
        try await send(frame: frame)
        try await stop()
    }

    fileprivate func resubscribe() async {
        for topic in topics {
            var headers = [String: String]()
            headers["destination"] = topic.value.destination
            headers["ack"] = topic.value.ack.rawValue
            headers["id"] = topic.key
            if let receipt = topic.value.receipt {
                headers["receipt"] = receipt
            }

            let frame = STOMPFrame(head: STOMPFrameHead(command: .SUBSCRIBE, headers: headers))
            try? await send(frame: frame)
        }
    }

    public func subscribe(id: String, destination: String, ack: Ack = .auto, receipt: String? = nil) async throws {
        let topic = Topic(destination: destination, ack: ack, receipt: receipt)
        topics[id] = topic

        var headers = [String: String]()
        headers["destination"] = topic.destination
        headers["ack"] = topic.ack.rawValue
        headers["id"] = id
        if let receipt = topic.receipt {
            headers["receipt"] = receipt
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .SUBSCRIBE, headers: headers))
        try await send(frame: frame)
    }

    public func unsubscribe(id: String, receipt: String? = nil) async throws {
        topics.removeValue(forKey: id)

        var headers = [String: String]()
        headers["id"] = id
        if let receipt {
            headers["receipt"] = receipt
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .UNSUBSCRIBE, headers: headers))
        try await send(frame: frame)
    }

    public func send(destination: String, payload: Data, contentType: String = "text/plain", transaction: String? = nil, receipt: String? = nil) async throws {
        var headers = [String: String]()
        headers["destination"] = destination
        if let transaction {
            headers["transaction"] = transaction
        }
        if let receipt {
            headers["receipt"] = receipt
        }
        headers["content-type"] = contentType
        headers["content-length"] = "\(payload.count)"

        let frame = STOMPFrame(head: STOMPFrameHead(command: .SEND, headers: headers), body: payload)
        try await send(frame: frame)
    }

    public func begin(transactionId: String, receipt: String? = nil) async throws {
        var headers = [String: String]()
        headers["transaction"] = transactionId
        if let receipt {
            headers["receipt"] = receipt
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .BEGIN, headers: headers))
        try await send(frame: frame)
    }

    public func commit(transaction: String, receipt: String? = nil) async throws {
        var headers = [String: String]()
        headers["transaction"] = transaction
        if let receipt {
            headers["receipt"] = receipt
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .COMMIT, headers: headers))
        try await send(frame: frame)
    }

    public func ack(id: String, transaction: String?) async throws {
        var headers = [String: String]()
        headers["id"] = id
        if let transaction {
            headers["transaction"] = transaction
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .ACK, headers: headers))
        try await send(frame: frame)
    }

    public func nack(id: String, transaction: String?) async throws {
        var headers = [String: String]()
        headers["id"] = id
        if let transaction {
            headers["transaction"] = transaction
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .NACK, headers: headers))
        try await send(frame: frame)
    }

    public func abort(transaction: String, receipt: String? = nil) async throws {
        var headers = [String: String]()
        headers["transaction"] = transaction
        if let receipt {
            headers["receipt"] = receipt
        }

        let frame = STOMPFrame(head: STOMPFrameHead(command: .ABORT, headers: headers))
        try await send(frame: frame)
    }

    private func sendConnectAndWaitConnected(frame: STOMPFrame) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard installConnectWaiter(continuation) else {
                continuation.resume(throwing: STOMPError.alreadyConnecting)
                return
            }

            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await self.send(frame: frame)
                } catch {
                    self.resumeConnectWaiter(.failure(error))
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: self.connectResponseTimeoutNanoseconds)
                    self.resumeConnectWaiter(.failure(STOMPError.connectionTimeout))
                } catch {
                    return
                }
            }
        }
    }

    private func installConnectWaiter(_ continuation: CheckedContinuation<Void, Error>) -> Bool {
        connectWaiterLock.lock()
        defer { connectWaiterLock.unlock() }
        guard connectWaiter == nil else { return false }
        connectWaiter = continuation
        return true
    }

    private func resumeConnectWaiter(_ result: Result<Void, Error>) {
        connectWaiterLock.lock()
        let continuation = connectWaiter
        connectWaiter = nil
        connectWaiterLock.unlock()

        guard let continuation else { return }

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    // MARK: - EventLoopFuture compatibility wrappers

    public func reconnectFuture(subscribe: Bool) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.reconnect(subscribe: subscribe)
        }
    }

    public func connectFuture(username: String, password: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.connect(username: username, password: password, receipt: receipt)
        }
    }

    public func disconnectFuture(receipt: String? = nil) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.disconnect(receipt: receipt)
        }
    }

    public func subscribeFuture(id: String, destination: String, ack: Ack = .auto, receipt: String? = nil) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.subscribe(id: id, destination: destination, ack: ack, receipt: receipt)
        }
    }

    public func unsubscribeFuture(id: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.unsubscribe(id: id, receipt: receipt)
        }
    }

    public func sendFuture(destination: String, payload: Data, contentType: String = "text/plain", transaction: String? = nil, receipt: String? = nil) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.send(destination: destination, payload: payload, contentType: contentType, transaction: transaction, receipt: receipt)
        }
    }

    public func beginFuture(transactionId: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.begin(transactionId: transactionId, receipt: receipt)
        }
    }

    public func commitFuture(transaction: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.commit(transaction: transaction, receipt: receipt)
        }
    }

    public func ackFuture(id: String, transaction: String?) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.ack(id: id, transaction: transaction)
        }
    }

    public func nackFuture(id: String, transaction: String?) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.nack(id: id, transaction: transaction)
        }
    }

    public func abortFuture(transaction: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        eventLoopGroup.next().makeFutureWithTask {
            try await self.abort(transaction: transaction, receipt: receipt)
        }
    }
}

public enum Ack: String, Sendable {
    case auto = "auto"
    case client = "client"
    case clientIndividual = "client-individual"
}

public struct Topic: Sendable {
    public var destination: String
    public var ack: Ack
    public var receipt: String?
}
