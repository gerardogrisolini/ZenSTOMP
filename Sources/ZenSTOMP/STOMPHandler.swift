//
//  STOMPHandler.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO


public typealias STOMPMessageReceived = (STOMPFrame) -> ()
public typealias STOMPHandlerRemoved = () -> ()
public typealias STOMPErrorCaught = (Error) -> ()


final class STOMPHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = STOMPFrame
    public typealias OutboundOut = STOMPFrame

    public var messageReceived: STOMPMessageReceived? = nil
    public var handlerRemoved: STOMPHandlerRemoved? = nil
    public var errorCaught: STOMPErrorCaught? = nil

    public init() {
    }

    public func channelActive(context: ChannelHandlerContext) {
        debugPrint("STOMP Client connected to \(context.remoteAddress!)")
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)

        debugPrint("channelRead: \(frame.head)")

        if frame.head.command == .MESSAGE {
            if let id = frame.head.headers["ack"] {
                let transaction = frame.head.headers["transaction"]
                ack(context, id, transaction)
            }
            if let messageReceived = messageReceived {
                messageReceived(frame)
            }
        }
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        guard let handlerRemoved = handlerRemoved else { return }
        handlerRemoved()
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)

        guard let errorCaught = errorCaught else { return }
        errorCaught(error)
    }

    private func ack(_ context: ChannelHandlerContext, _ id: String, _ transaction: String?) {
        var headers = Dictionary<String, String>()
        headers["id"] = id
        if let transaction = transaction {
            headers["transaction"] = transaction
        }
        let frame = STOMPFrame(head: STOMPFrameHead(command: .ACK, headers: headers))
        context.writeAndFlush(self.wrapOutboundOut(frame), promise: nil)
    }
}

