//
//  STOMPFrameEncoder.swift
//  
//
//  Created by Gerardo Grisolini on 26/01/2020.
//

import NIO

public final class STOMPFrameEncoder: MessageToByteEncoder {
    public typealias OutboundIn = STOMPFrame

    let NULL_BYTE: UInt8 = 0x00
    let LINEFEED_BYTE: UInt8 = 0x0a
    let COLON_BYTE: UInt8 = 0x3a
    let SPACE_BYTE: UInt8 = 0x20

    public func encode(data value: STOMPFrame, out: inout ByteBuffer) throws {
        out.writeString(value.head.command.rawValue)
        out.writeBytes([LINEFEED_BYTE])
        for header in value.head.headers {
            out.writeString(header.key)
            out.writeBytes([COLON_BYTE])
            out.writeString(header.value)
            out.writeBytes([LINEFEED_BYTE])
        }
        out.writeBytes([LINEFEED_BYTE])
        out.writeBytes(value.body)
        out.writeBytes([NULL_BYTE])
    }
}
