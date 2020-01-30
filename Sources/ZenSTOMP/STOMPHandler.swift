//
//  STOMPHandler.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO

final class STOMPHandler: ChannelInboundHandler, RemovableChannelHandler {
    public typealias InboundIn = STOMPFramePart
    public typealias OutboundOut = STOMPFramePart
    public var isConnected: Bool
    private var receiver: STOMPMessage? = nil
    private var message: STOMPFrame!

    init() {
        isConnected = false
    }
    
    func setReceiver(receiver: @escaping STOMPMessage) {
        self.receiver = receiver
    }

    public func channelActive(context: ChannelHandlerContext) {
        print("Client connected to \(context.remoteAddress!)")
        isConnected = true
    }
    
    private func ack(_ context: ChannelHandlerContext, _ messageId: String, _ subscription: String) {
        var headers = Dictionary<String, String>()
        headers["message-id"] = messageId
        headers["subscription"] = subscription
        let head = STOMPFrameHead(command: .ACK, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }
        
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        switch frame {
        case .head(let responseHead):
            message = STOMPFrame(head: responseHead)
            if responseHead.command == .MESSAGE,
                let messageId = responseHead.headers["message-id"],
                let subscription = responseHead.headers["subscription"] {
                ack(context, messageId, subscription)
            }
        case .body(var byteBuffer):
            if let bytes = byteBuffer.readBytes(length: byteBuffer.readableBytes) {
                message.body += Data(bytes)
            }
        case .end(_):
            receiver?(message)
            break
        }
    }
    
    public func handlerRemoved(context: ChannelHandlerContext) {
        print("STOMP handler removed.")
        isConnected = false
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        // As we are not really interested getting notified on success or failure
        // we just pass nil as promise to reduce allocations.
        context.close(promise: nil)
    }
}
