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
        guard buffer.readableBytes >= 2 else { return .needMoreData }

        let (count, remainingLength) = try buffer.getRemainingLength(at: buffer.readerIndex + 1)
        guard buffer.readableBytes >= (1 + Int(count) + remainingLength) else { return .needMoreData }
        
        if let frame = parse(buffer: buffer) {
            context.fireChannelRead(self.wrapInboundOut(frame))
            buffer.clear()
            return .continue
        } else {
            return .needMoreData
        }
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        // EOF is not semantic in WebSocket, so ignore this.
        return .needMoreData
    }
    
    private func parse(buffer: ByteBuffer) -> STOMPFrame? {
        #if DEBUG
        print("STOMP Client parse: \(buffer.getString(at: 0, length: buffer.readableBytes))")
        #endif

        var index = 0
        let count = buffer.readableBytes
        for i in 0..<count {
            if buffer.getBytes(at: i, length: 2) == [0x0a,0x0a] {
                index = i + 2
                break
            }
        }
        
        if let string = buffer.getString(at: 0, length: index),
            let bytes = buffer.getBytes(at: index, length: count - index - 2) {
            
            #if DEBUG
            print("STOMP Client header: \(string)")
            #endif
            
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
            
            return STOMPFrame(head: head, body: Data(bytes))
        }
        
        return nil
    }
}

extension ByteBuffer {
    func getRemainingLength(at newReaderIndex: Int) throws -> (count: UInt8, length: Int) {
        var multiplier: UInt32 = 1
        var value: Int = 0
        var byte: UInt8 = 0
        var currentIndex = newReaderIndex
        repeat {
            guard currentIndex != (readableBytes + 1) else { throw RemainingLengthError.incomplete }
            
            guard multiplier <= (128 * 128 * 128) else { throw RemainingLengthError.malformed }
            
            guard let nextByte: UInt8 = getInteger(at: currentIndex) else { throw RemainingLengthError.incomplete }
            
            byte = nextByte
            
            value += Int(UInt32(byte & 127) * multiplier)
            multiplier *= 128
            currentIndex += 1
        } while ((byte & 128) != 0)// && !isEmpty
        
        return (count: UInt8(currentIndex - newReaderIndex), length: value)
    }
}

public enum RemainingLengthError: Error {
    case incomplete
    case malformed
}
