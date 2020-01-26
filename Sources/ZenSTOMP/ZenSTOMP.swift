//
//  ZenSTOMP.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO
import NIOSSL


public typealias OnResponse = (STOMPFrame) -> ()

public class ZenSTOMP {
    private let host: String
    private let port: Int
    private let eventLoopGroup: EventLoopGroup
    private var channel: Channel!
    public var onResponse: OnResponse = { _ in }
    
    private var sslClientHandler: NIOSSLClientHandler? = nil
    
    init(host: String, port: Int, eventLoopGroup: EventLoopGroup? = nil) {
        self.host = host
        self.port = port
        self.eventLoopGroup = eventLoopGroup ?? MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
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

    public func start(keepAlive: Int64 = 0) -> EventLoopFuture<Void> {
        let handlers: [ChannelHandler] = [
            STOMPFrameDecoder(),
            STOMPFrameEncoder(),
            STOMPHandler(onResponse: self.onResponse)
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
                if keepAlive > 0 {
                    self.keepAlive(time: TimeAmount.seconds(keepAlive))
                }
            }
    }
    
    public func stop() {
        channel.flush()
        channel.close(promise: nil)
    }
    
    private func keepAlive(time: TimeAmount) {
        channel.eventLoop.scheduleRepeatedAsyncTask(initialDelay: time, delay: time) { task -> EventLoopFuture<Void> in
            var headers = Dictionary<String, String>()
            headers["destination"] = "*"
            let head = STOMPFrameHead(command: .SEND, headers: headers)
            self.channel.write(STOMPFramePart.head(head), promise: nil)
            return self.channel.writeAndFlush(STOMPFramePart.end(nil))
        }
    }

    public func connect(username: String, password: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
//        headers["accept-version"] = "1.2"
//        headers["heart-beat"] = "0,0"
        headers["login"] = username
        headers["passcode"] = password
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .CONNECT, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }

    public func disconnect(receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .DISCONNECT, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }

    public func subscribe(id: String, destination: String, ack: String = "auto", receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["destination"] = destination
        headers["ack"] = ack
        headers["id"] = id
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .SUBSCRIBE, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }

    public func unsubscribe(id: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["id"] = id
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .UNSUBSCRIBE, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }

    public func send(destination: String, payload: Data, contentType: String = "text/plain", transaction: String? = nil, receipt: String? = nil) {
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

        let head = STOMPFrameHead(command: .SEND, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        var buffer = channel.allocator.buffer(capacity: payload.count)
        buffer.writeBytes(payload)
        channel.write(STOMPFramePart.body(buffer), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }
    
    public func begin(transactionId: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transactionId
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .BEGIN, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }

    public func commit(transaction: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transaction
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .COMMIT, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }
    
    public func ack(id: String, transaction: String?) {
        var headers = Dictionary<String, String>()
        headers["id"] = id
        if let transaction = transaction {
            headers["transaction"] = transaction
        }
        let head = STOMPFrameHead(command: .ACK, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }

    public func nack(id: String, transaction: String?) {
        var headers = Dictionary<String, String>()
        headers["id"] = id
        if let transaction = transaction {
            headers["transaction"] = transaction
        }
        let head = STOMPFrameHead(command: .NACK, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }
    
    public func abort(transaction: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transaction
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .ABORT, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.writeAndFlush(STOMPFramePart.end(nil), promise: nil)
    }
}
