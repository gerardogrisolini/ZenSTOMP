//
//  STOMPFrameDecoder.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO

final class STOMPFrameDecoder: ByteToMessageDecoder {
    public typealias InboundOut = STOMPFrame

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState  {
        guard buffer.readableBytes >= 5 else { return .needMoreData }
        
        if let frame = parse(buffer: &buffer) {
            context.fireChannelRead(self.wrapInboundOut(frame))
            return .continue
        }

        return .needMoreData
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        try decode(context: context, buffer: &buffer)
    }
    
    public func parse(buffer: inout ByteBuffer) -> STOMPFrame? {
        let len = buffer.getRemainingLength(at: buffer.readerIndex)
        
        if len > 0, let string = buffer.getString(at: buffer.readerIndex, length: len) {
            var head = STOMPFrameHead()
            let rows = string.split(separator: "\n", omittingEmptySubsequences: true)
            for row in rows {
                if row.contains(":") {
                    let cols = row.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: true)
                    let key = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    head.headers[key] = value
                } else if let command = Command(rawValue: row.description) {
                    head.command = command
                }
            }
            buffer.moveReaderIndex(forwardBy: len)

            let lenght = Int(head.headers["content-length"] ?? buffer.readableBytes.description)!
            if let bytes = buffer.getBytes(at: buffer.readerIndex, length: lenght) {
                buffer.moveReaderIndex(forwardBy: lenght)
                return STOMPFrame(head: head, body: Data(bytes))
            }
        }
        
        return nil
    }
}

extension ByteBuffer {
    func getRemainingLength(at newReaderIndex: Int) -> Int {
        for i in 0..<readableBytes {
            if i > 5 && getBytes(at: i, length: 2) == [0x0a,0x0a] {
                return i + 2
            }
        }
        return 0
    }
}
