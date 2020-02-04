//
//  ZenSTOMP.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO
import NIOSSL


enum STOMPError : Error {
    case connectionError
}

public class ZenSTOMP {
    private let host: String
    private let port: Int
    private let eventLoopGroup: EventLoopGroup
    private var channel: Channel? = nil
    private var sslClientHandler: NIOSSLClientHandler? = nil
    private let handler = STOMPHandler()

    private var keepAlive: Int64 = 0
    private var destination: String = "*"
    private var message: String? = nil

    public var version: String? = nil // "1.2,1.1"
    public var heartBeat: String? = nil // "8000,8000"

    public var onMessageReceived: STOMPMessageReceived? = nil
    public var onHandlerRemoved: STOMPHandlerRemoved? = nil
    public var onErrorCaught: STOMPErrorCaught? = nil

    public init(host: String, port: Int, eventLoopGroup: EventLoopGroup) {
        self.host = host
        self.port = port
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
        
        let sslContext = try NIOSSLContext(configuration: config)
        sslClientHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
    }

    public func addKeepAlive(seconds: Int64, destination: String = "*", message: String? = nil) {
        keepAlive = seconds
        self.destination = destination
        self.message = message
    }
    
    private func start() -> EventLoopFuture<Void> {

        handler.messageReceived = onMessageReceived
        handler.handlerRemoved = onHandlerRemoved
        handler.errorCaught = onErrorCaught

        let handlers: [ChannelHandler] = [
            MessageToByteHandler(STOMPFrameEncoder()),
            ByteToMessageHandler(STOMPFrameDecoder()),
            handler
        ]
        
        return ClientBootstrap(group: eventLoopGroup)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
            .channelInitializer { channel in
                if let ssl = self.sslClientHandler {
                    return channel.pipeline.addHandler(ssl).flatMap { () -> EventLoopFuture<Void> in
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
        guard let channel = channel else {
            return eventLoopGroup.next().makeFailedFuture(STOMPError.connectionError)
        }
        
        channel.flush()
        return channel.close()
    }

    private func send(frame: STOMPFrame) -> EventLoopFuture<Void> {
        guard let channel = channel else {
            return eventLoopGroup.next().makeFailedFuture(STOMPError.connectionError)
        }
        
        return channel.writeAndFlush(frame)
    }
    
    private func startKeepAlive() {
        guard let channel = channel, keepAlive > 0 else { return }

        let time = TimeAmount.seconds(keepAlive)
        channel.eventLoop.scheduleRepeatedAsyncTask(initialDelay: time, delay: time) { task -> EventLoopFuture<Void> in
            var headers = Dictionary<String, String>()
            headers["destination"] = self.destination
            var frame = STOMPFrame(head: STOMPFrameHead(command: .SEND, headers: headers))
            if let body = self.message?.data(using: .utf8) {
                frame.body = body
            }
            return self.send(frame: frame)
        }
    }

    public func connect(username: String, password: String, receipt: String? = nil) -> EventLoopFuture<Void> {
        return start().flatMap { () -> EventLoopFuture<Void> in
            var headers = Dictionary<String, String>()
            headers["accept-version"] = self.version
            headers["heart-beat"] = self.heartBeat
            headers["login"] = username
            headers["passcode"] = password
            if let receipt = receipt {
                headers["receipt"] = receipt
            }
            let frame = STOMPFrame(head: STOMPFrameHead(command: .CONNECT, headers: headers))
            return self.send(frame: frame).map { () -> () in
                self.startKeepAlive()
            }
        }
    }

    public func disconnect(receipt: String? = nil) -> EventLoopFuture<Void> {
        var headers = Dictionary<String, String>()
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .DISCONNECT, headers: headers))
        return self.send(frame: frame).flatMap { () -> EventLoopFuture<Void> in
            return self.stop()
        }
    }

    public func subscribe(id: String, destination: String, ack: Ack = .auto, receipt: String? = nil) -> EventLoopFuture<Void> {
        var headers = Dictionary<String, String>()
        headers["destination"] = destination
        headers["ack"] = ack.rawValue
        headers["id"] = id
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .SUBSCRIBE, headers: headers))
        return self.send(frame: frame)
    }

    public func unsubscribe(id: String, receipt: String? = nil) -> EventLoopFuture<Void> {
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
