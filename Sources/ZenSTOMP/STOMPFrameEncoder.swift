//
//  STOMPFrameEncoder.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import NIO

final class STOMPFrameEncoder: ChannelOutboundHandler {
    public typealias OutboundIn = STOMPFramePart
    public typealias OutboundOut = ByteBuffer

    let NULL_BYTE: UInt8 = 0x00
    let LINEFEED_BYTE: UInt8 = 0x0a
    let COLON_BYTE: UInt8 = 0x3a
    let SPACE_BYTE: UInt8 = 0x20

    public init () { }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let frame = self.unwrapOutboundIn(data)
        
        switch frame {
        case .head(let head):
            var buffer = context.channel.allocator.buffer(capacity: 1024)
            buffer.writeString(head.command.rawValue)
            buffer.writeBytes([LINEFEED_BYTE])
            for header in head.headers {
                buffer.writeString(header.key)
                buffer.writeBytes([COLON_BYTE, SPACE_BYTE])
                buffer.writeString(header.value)
                buffer.writeBytes([LINEFEED_BYTE])
            }
            buffer.writeBytes([LINEFEED_BYTE])
            context.write(self.wrapOutboundOut(buffer), promise: promise)
            print("REQUEST: \(head)")
        case .body(let body):
            context.write(self.wrapOutboundOut(body), promise: promise)
        case .end(_):
            var buffer = context.channel.allocator.buffer(capacity: 1)
            buffer.writeBytes([NULL_BYTE])
            context.writeAndFlush(self.wrapOutboundOut(buffer), promise: promise)
        }
    }
}
