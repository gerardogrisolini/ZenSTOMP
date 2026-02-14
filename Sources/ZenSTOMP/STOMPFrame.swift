//
//  STOMPFrame.swift
//
//
//  Created by Gerardo Grisolini on 25/01/2020.
//

import Foundation
@preconcurrency import NIO

public enum Command: String, Sendable {
    case ABORT, ACK, NACK, BEGIN, COMMIT, CONNECT, DISCONNECT, SEND, SUBSCRIBE, UNSUBSCRIBE
    case CONNECTED, MESSAGE, RECEIPT, ERROR
}

public struct STOMPFrameHead: Equatable, Sendable {
    public var command: Command = .CONNECT
    public var headers: [String: String] = [:]
}

public struct STOMPFrame: Equatable, Sendable {
    public static func == (lhs: STOMPFrame, rhs: STOMPFrame) -> Bool {
        lhs.head == rhs.head
    }

    public var head: STOMPFrameHead
    public var body: Data = Data()
}
