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
        guard buffer.readableBytes >= (1 + Int(count) + remainingLength) else {
            return .needMoreData
        }
        
        let frames = parse(buffer: buffer)
        if frames.count > 0 {
            for frame in frames {
                context.fireChannelRead(self.wrapInboundOut(frame))
            }
            context.fireChannelReadComplete()
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
    
    public func bodyIndexes(buffer: ByteBuffer) -> [Int] {
        var indexes: [Int] = []
        let count = buffer.readableBytes
        for i in 0..<count {
            if i > 5 && buffer.getBytes(at: i, length: 2) == [0x0a,0x0a] {
                indexes.append(i + 2)
            }
        }
        return indexes
    }
    
    public func parse(buffer: ByteBuffer) -> [STOMPFrame] {
        var frames = [STOMPFrame]()
        
        let indexes = bodyIndexes(buffer: buffer)
        for i in 0..<indexes.count {
            
            let start = i == 0 ? 0 : indexes[i - 1]
            let index = indexes[i]
            
            if let string = buffer.getString(at: start, length: index - start) {

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

                var len = buffer.readableBytes - index - 2
                if let l = head.headers["content-length"] {
                    len = Int(l)!
                }
                
                if let bytes = buffer.getBytes(at: index, length: len) {
                    //print("\n\n__________________")
                    //print(string)
                    //print(String(bytes: bytes, encoding: .utf8)!)
                    frames.append(STOMPFrame(head: head, body: Data(bytes)))
                }
            }
        }
        
        return frames
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
