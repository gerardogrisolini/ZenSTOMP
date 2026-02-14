//
//  STOMPHandler.swift
//
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
@preconcurrency import NIO

public typealias STOMPMessageReceived = @Sendable (STOMPFrame) -> Void
public typealias STOMPConnected = @Sendable (STOMPFrame) -> Void
public typealias STOMPServerError = @Sendable (STOMPFrame) -> Void
public typealias STOMPHandlerRemoved = @Sendable () -> Void
public typealias STOMPErrorCaught = @Sendable (Error) -> Void

final class STOMPHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    public typealias InboundIn = STOMPFrame
    public typealias OutboundOut = STOMPFrame

    public var messageReceived: STOMPMessageReceived? = nil
    public var connected: STOMPConnected? = nil
    public var serverError: STOMPServerError? = nil
    public var handlerRemoved: STOMPHandlerRemoved? = nil
    public var errorCaught: STOMPErrorCaught? = nil

    public init() {}

    public func channelActive(context: ChannelHandlerContext) {
        #if DEBUG
        print("STOMP Client connected to \(String(describing: context.remoteAddress))")
        #endif
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)

        if frame.head.command == .CONNECTED {
            connected?(frame)
            return
        }

        if frame.head.command == .ERROR {
            serverError?(frame)
            return
        }

        if frame.head.command == .MESSAGE {
            if let id = frame.head.headers["ack"] {
                let transaction = frame.head.headers["transaction"]
                ack(context, id, transaction)
            }
            messageReceived?(frame)
        }
    }

    public func handlerRemoved(context: ChannelHandlerContext) {
        handlerRemoved?()
    }

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
        errorCaught?(error)
    }

    private func ack(_ context: ChannelHandlerContext, _ id: String, _ transaction: String?) {
        var headers = [String: String]()
        headers["id"] = id
        if let transaction {
            headers["transaction"] = transaction
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .ACK, headers: headers))
        context.writeAndFlush(self.wrapOutboundOut(frame), promise: nil)
    }
}
