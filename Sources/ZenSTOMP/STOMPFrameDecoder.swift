//
//  STOMPFrameDecoder.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import NIO

final class STOMPFrameDecoder: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = STOMPFramePart
    public typealias OutboundOut = STOMPFramePart

    public init () { }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var byteBuffer = self.unwrapInboundIn(data)
        
        if let string = byteBuffer.readString(length: byteBuffer.readableBytes) {
            var head = STOMPFrameHead()
            var isBody = false
            let rows = string.split(separator: "\n", omittingEmptySubsequences: false)
            for row in rows {
                
                if isBody && row.isEmpty { continue }
                
                if row.isEmpty {
                    context.fireChannelRead(self.wrapInboundOut(.head(head)))
                    isBody = true
                    continue
                } else if isBody {
                    byteBuffer.clear()
                    byteBuffer.reserveCapacity(row.utf8.count)
                    byteBuffer.writeString(row.description)
                    context.fireChannelRead(self.wrapInboundOut(.body(byteBuffer)))
                    continue
                }
                
                if row.contains(":") {
                    let cols = row.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: true)
                    head.headers[cols[0].description] = cols[1].description
                } else if !isBody, let command = Command(rawValue: row.description) {
                    head.command = command
                }
            }
        }
        
        context.fireChannelRead(self.wrapInboundOut(.end(nil)))
    }
}
