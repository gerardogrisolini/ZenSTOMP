//
//  STOMPFrameDecoder.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import Foundation
import NIO

enum STOMPFrameDecoderError: Error {
    case invalidFrame(String)
    case invalidContentLength(String)
    case missingNullTerminator
}

final class STOMPFrameDecoder: ByteToMessageDecoder {
    public typealias InboundOut = STOMPFrame

    public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes >= 2 else { return .needMoreData }

        if let frame = try parse(buffer: &buffer) {
            context.fireChannelRead(self.wrapInboundOut(frame))
            return .continue
        }

        return .needMoreData
    }

    public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        try decode(context: context, buffer: &buffer)
    }

    func parse(buffer: inout ByteBuffer) throws -> STOMPFrame? {
        let start = buffer.readerIndex
        let end = buffer.writerIndex

        guard let (headerEnd, headerDelimiterLength) = buffer.findHeaderTerminator(from: start, to: end) else {
            return nil
        }

        let headerLength = headerEnd - start
        guard let headerBlock = buffer.getString(at: start, length: headerLength) else {
            throw STOMPFrameDecoderError.invalidFrame("Header is not valid UTF-8")
        }

        let head = try Self.parseHead(from: headerBlock)
        let bodyStart = headerEnd + headerDelimiterLength

        let bodyLength: Int
        if let lengthValue = head.headers["content-length"] {
            guard let parsedLength = Int(lengthValue), parsedLength >= 0 else {
                throw STOMPFrameDecoderError.invalidContentLength(lengthValue)
            }
            bodyLength = parsedLength

            let nullIndex = bodyStart + bodyLength
            guard nullIndex < end else { return nil }
            guard buffer.getInteger(at: nullIndex, as: UInt8.self) == 0x00 else {
                throw STOMPFrameDecoderError.missingNullTerminator
            }
        } else {
            guard let nullIndex = buffer.firstIndex(of: 0x00, from: bodyStart, to: end) else {
                return nil
            }
            bodyLength = nullIndex - bodyStart
        }

        guard let bytes = buffer.getBytes(at: bodyStart, length: bodyLength) else {
            return nil
        }

        buffer.moveReaderIndex(to: bodyStart + bodyLength + 1)

        while let next = buffer.getInteger(at: buffer.readerIndex, as: UInt8.self), next == 0x0a || next == 0x0d {
            buffer.moveReaderIndex(forwardBy: 1)
        }

        return STOMPFrame(head: head, body: Data(bytes))
    }

    private static func parseHead(from headerBlock: String) throws -> STOMPFrameHead {
        var head = STOMPFrameHead()
        var parsedCommand: Command?

        for rawLine in headerBlock.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if parsedCommand == nil, let command = Command(rawValue: String(line)) {
                parsedCommand = command
                continue
            }

            guard let separator = line.firstIndex(of: ":") else {
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            head.headers[key] = value
        }

        guard let command = parsedCommand else {
            throw STOMPFrameDecoderError.invalidFrame("Missing STOMP command")
        }

        head.command = command
        return head
    }
}

extension ByteBuffer {
    fileprivate func findHeaderTerminator(from start: Int, to end: Int) -> (headerEnd: Int, delimiterLength: Int)? {
        guard start < end else { return nil }
        var index = start
        while index + 1 < end {
            guard let b0 = getInteger(at: index, as: UInt8.self),
                  let b1 = getInteger(at: index + 1, as: UInt8.self) else {
                return nil
            }

            if b0 == 0x0a, b1 == 0x0a {
                return (index, 2)
            }

            if index + 3 < end,
               let b2 = getInteger(at: index + 2, as: UInt8.self),
               let b3 = getInteger(at: index + 3, as: UInt8.self),
               b0 == 0x0d, b1 == 0x0a, b2 == 0x0d, b3 == 0x0a {
                return (index, 4)
            }

            index += 1
        }

        return nil
    }

    fileprivate func firstIndex(of value: UInt8, from start: Int, to end: Int) -> Int? {
        guard start < end else { return nil }
        var index = start
        while index < end {
            if getInteger(at: index, as: UInt8.self) == value {
                return index
            }
            index += 1
        }
        return nil
    }
}
