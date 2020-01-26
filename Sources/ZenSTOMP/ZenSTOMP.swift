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
    public let host: String
    public let port: Int
    private let eventLoopGroup: EventLoopGroup
    private var sslContext: NIOSSLContext? = nil
    private var channel: Channel!
    public var onResponse: OnResponse = { _ in }
    
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
        
        sslContext = try NIOSSLContext(configuration: config)
    }

    public func start() -> EventLoopFuture<Void> {
        return ClientBootstrap(group: eventLoopGroup)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                if let ssl = self.sslContext {
                    return channel.pipeline.addHandler(try! NIOSSLClientHandler(context: ssl, serverHostname: self.host)).flatMap { () -> EventLoopFuture<Void> in
                        return channel.pipeline.addHandlers([
                            STOMPFrameDecoder(),
                            STOMPFrameEncoder(),
                            STOMPHandler(onResponse: self.onResponse)
                        ])
                    }
                } else {
                    return channel.pipeline.addHandlers([
                        STOMPFrameDecoder(),
                        STOMPFrameEncoder(),
                        STOMPHandler(onResponse: self.onResponse)
                    ])
                }
            }
            .connect(host: host, port: port)
            .map { channel -> () in
                self.channel = channel
            }
    }
    
    public func stop() {
        channel.close(promise: nil)
    }
    
    public func connect(username: String, password: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        //headers["accept-version"] = "1.2"
        headers["login"] = username
        headers["passcode"] = password
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .CONNECT, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.write(STOMPFramePart.end(nil), promise: nil)
    }

    public func disconnect(receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .DISCONNECT, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.write(STOMPFramePart.end(nil), promise: nil)
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
        channel.write(STOMPFramePart.end(nil), promise: nil)
    }

    public func unsubscribe(id: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["id"] = id
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .UNSUBSCRIBE, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.write(STOMPFramePart.end(nil), promise: nil)
    }

    public func send(destination: String, payload: Data, contentType: String = "text/plain", transactionId: String? = nil, receipt: String? = nil) {
        let lenght = payload.count
        var headers = Dictionary<String, String>()
        headers["destination"] = destination
        if let transactionId = transactionId {
            headers["transaction"] = transactionId
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
        channel.write(STOMPFramePart.end(nil), promise: nil)
    }
    
    public func begin(transactionId: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transactionId
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .BEGIN, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.write(STOMPFramePart.end(nil), promise: nil)
    }

    public func commit(transactionId: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transactionId
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .COMMIT, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.write(STOMPFramePart.end(nil), promise: nil)
    }
    
    public func ack(messageId: String, transactionId: String?, subscription: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["message-id"] = messageId
        if let transactionId = transactionId {
            headers["transaction"] = transactionId
        }
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        headers["subscription"] = subscription
        let head = STOMPFrameHead(command: .ACK, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.write(STOMPFramePart.end(nil), promise: nil)
    }

    public func abort(transactionId: String, receipt: String? = nil) {
        var headers = Dictionary<String, String>()
        headers["transaction"] = transactionId
        if let receipt = receipt {
            headers["receipt"] = receipt
        }
        let head = STOMPFrameHead(command: .ABORT, headers: headers)
        channel.write(STOMPFramePart.head(head), promise: nil)
        channel.write(STOMPFramePart.end(nil), promise: nil)
    }
}
