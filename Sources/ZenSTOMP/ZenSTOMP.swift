//
//  ZenSTOMP.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO
import NIOSSL

public struct HeartBeat {
    let send: Int
    let recv: Int
    var string: String { "\(send),\(recv)" }
    
    public init(send: Int = 0, recv: Int = 0) {
        self.send = send
        self.recv = recv
    }
}

enum STOMPError : Error {
    case connectionError
}

public class ZenSTOMP {
    private let host: String
    private let port: Int
    private let eventLoopGroup: EventLoopGroup
    private var channel: Channel? = nil
    private var sslContext: NIOSSLContext? = nil
    private let handler = STOMPHandler()
    private var repeatedTask: RepeatedTask? = nil
    
    private var username: String?
    private var password: String?
    private var receipt: String?
    private var topics = [String : Topic]()
    private var autoreconnect: Bool = false
    private var keepAlive: Int64 = 0
    private var destination: String = "*"
    private var message: String? = nil
    public var version: String = "1.2"
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
        let cert = try NIOSSLCertificate.fromPEMFile(cert)
        let key = try NIOSSLPrivateKey.init(file: key, format: .pem)
        
        let config = TLSConfiguration.forClient(
            certificateVerification: .none,
            certificateChain: [.certificate(cert.first!)],
            privateKey: .privateKey(key)
        )
        
        sslContext = try NIOSSLContext(configuration: config)
    }

    private func start() -> EventLoopFuture<Void> {
        
        let handlers: [ChannelHandler] = [
            MessageToByteHandler(STOMPFrameEncoder()),
            ByteToMessageHandler(STOMPFrameDecoder()),
            handler
        ]
        
        return ClientBootstrap(group: eventLoopGroup)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
            .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
            .channelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .channelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            .channelOption(ChannelOptions.connectTimeout, value: TimeAmount.seconds(8))
            .channelInitializer { channel in
                if let sslContext = self.sslContext {
                    let sslClientHandler = try! NIOSSLClientHandler(context: sslContext, serverHostname: self.host)
                    return channel.pipeline.addHandler(sslClientHandler).flatMap { () -> EventLoopFuture<Void> in
                        channel.pipeline.addHandlers(handlers)
                    }
                } else {
                    return channel.pipeline.addHandlers(handlers)
                }
        }
        .connect(host: host, port: port)
        .map { channel -> () in
            self.channel = channel
        }
    }
    
    private func stop() -> EventLoopFuture<Void> {
        repeatedTask?.cancel()
        
        guard let channel = channel else {
            return eventLoopGroup.next().makeFailedFuture(STOMPError.connectionError)
        }
        
        channel.flush()
        return channel.close(mode: .all).map { () -> () in
            self.channel = nil
        }
    }

    private func send(frame: STOMPFrame) -> EventLoopFuture<Void> {
        guard let channel = channel else {
            return eventLoopGroup.next().makeFailedFuture(STOMPError.connectionError)
        }
        
        return channel.writeAndFlush(frame)
    }
    
    private func startKeepAlive() {
        repeatedTask?.cancel()
        
        guard let channel = channel, keepAlive > 0 else { return }

        var headers = Dictionary<String, String>()
        headers["destination"] = self.destination
        var frame = STOMPFrame(head: STOMPFrameHead(command: .SEND, headers: headers))
        if let body = self.message?.data(using: .utf8) {
            frame.body = body
        }

        let time = TimeAmount.seconds(keepAlive)
        repeatedTask = channel.eventLoop.scheduleRepeatedTask(initialDelay: time, delay: time) { task -> () in
            self.send(frame: frame).whenComplete { _ in }
        }
    }

    public func addKeepAlive(seconds: Int64, destination: String = "*", message: String? = nil) {
        keepAlive = seconds
        self.destination = destination
        self.message = message
    }
    
    public func reconnect(subscribe: Bool) -> EventLoopFuture<Void> {
        return start().flatMap { () -> EventLoopFuture<Void> in
            var headers = Dictionary<String, String>()
            headers["accept-version"] = self.version
            headers["heart-beat"] = self.heartBeat.string
            headers["login"] = self.username
            headers["passcode"] = self.password
            if let receipt = self.receipt {
                headers["receipt"] = receipt
            }
            let frame = STOMPFrame(head: STOMPFrameHead(command: .CONNECT, headers: headers))
            return self.send(frame: frame).map { () -> () in
                if subscribe { self.resubscribe() }
                self.startKeepAlive()
            }
        }.flatMapError { err -> EventLoopFuture<Void> in
            return self.eventLoopGroup.next().makeFailedFuture(err)
        }
    }

    public func connect(username: String, password: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        self.username = username
        self.password = password
        self.receipt = receipt

        handler.messageReceived = onMessageReceived
        handler.errorCaught = onErrorCaught
        handler.handlerRemoved = {
            if let onHandlerRemoved = self.onHandlerRemoved {
                onHandlerRemoved()
            }
            
            if self.autoreconnect {
                sleep(3)
                self.reconnect(subscribe: true).whenComplete { _ in }
            }
        }
        
        return reconnect(subscribe: false)
    }
    
    public func disconnect(receipt: String? = nil) -> EventLoopFuture<Void> {
        autoreconnect = false

        var headers = Dictionary<String, String>()
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .DISCONNECT, headers: headers))
        return self.send(frame: frame).flatMap { () -> EventLoopFuture<Void> in
            return self.stop()
        }
    }

    fileprivate func resubscribe() {
        for topic in topics {
            var headers = Dictionary<String, String>()
            headers["destination"] = topic.value.destination
            headers["ack"] = topic.value.ack.rawValue
            headers["id"] = topic.key
            if let receipt = topic.value.receipt {
                headers["receipt"] = receipt
            }
            let frame = STOMPFrame(head: STOMPFrameHead(command: .SUBSCRIBE, headers: headers))
            self.send(frame: frame).whenComplete { _ in }
        }
    }

    public func subscribe(id: String, destination: String, ack: Ack = .auto, receipt: String? = nil) -> EventLoopFuture<Void> {
        let topic = Topic(destination: destination, ack: ack, receipt: receipt)
        topics[id] = topic
        
        var headers = Dictionary<String, String>()
        headers["destination"] = topic.destination
        headers["ack"] = topic.ack.rawValue
        headers["id"] = id
        if let receipt = topic.receipt {
            headers["receipt"] = receipt
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .SUBSCRIBE, headers: headers))
        return self.send(frame: frame)
    }

    public func unsubscribe(id: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        
        topics.removeValue(forKey: id)
        
        var headers = Dictionary<String, String>()
        headers["id"] = id
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .UNSUBSCRIBE, headers: headers))
        return self.send(frame: frame)
    }

    public func send(destination: String, payload: Data, contentType: String = "text/plain", transaction: String? = nil, receipt: String? = nil) -> EventLoopFuture<Void> {
        let lenght = payload.count
        var headers = Dictionary<String, String>()
        headers["destination"] = destination
        if let transaction = transaction {
            headers["transaction"] = transaction
        }
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        headers["content-type"] = contentType
        headers["content-length"] = "\(lenght)"
        let frame = STOMPFrame(head: STOMPFrameHead(command: .SEND, headers: headers), body: payload)
        return self.send(frame: frame)
    }
    
    public func begin(transactionId: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transactionId
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .BEGIN, headers: headers))
        return self.send(frame: frame)
    }

    public func commit(transaction: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transaction
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .COMMIT, headers: headers))
        return self.send(frame: frame)
    }
    
    public func ack(id: String, transaction: String?) -> EventLoopFuture<Void> {
        var headers = Dictionary<String, String>()
        headers["id"] = id
        if let transaction = transaction {
            headers["transaction"] = transaction
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .ACK, headers: headers))
        return self.send(frame: frame)
    }

    public func nack(id: String, transaction: String?) -> EventLoopFuture<Void> {
        var headers = Dictionary<String, String>()
        headers["id"] = id
        if let transaction = transaction {
            headers["transaction"] = transaction
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .NACK, headers: headers))
        return self.send(frame: frame)

    }
    
    public func abort(transaction: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transaction
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .ABORT, headers: headers))
        return self.send(frame: frame)
    }
}

public enum Ack : String {
    case auto = "auto"
    case client = "client"
    case clientIndividual = "client-individual"
}


public struct Topic {
    public var destination: String
    public var ack: Ack
    public var receipt: String?
}
