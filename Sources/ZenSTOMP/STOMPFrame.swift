//
//  STOMPFrame.swift
//  
//
//  Created by Gerardo Grisolini on 25/01/2020.
//

import Foundation
import NIO

public enum STOMPPart<HeadT, BodyT> where HeadT : Equatable, BodyT : Equatable {
    case head(HeadT)
    case body(BodyT)
    case end(Void?)
}

public enum Command: String {
    case ABORT, ACK, NACK, BEGIN, COMMIT, CONNECT, DISCONNECT, SEND, SUBSCRIBE, UNSUBSCRIBE // CLIENT
    case CONNECTED, MESSAGE, RECEIPT, ERROR // SERVER
}

public struct STOMPFrameHead: Equatable {
    public var command: Command = .CONNECT
    public var headers: Dictionary<String, String> = Dictionary<String, String>()
}

public struct STOMPFrame: Equatable {
    public static func == (lhs: STOMPFrame, rhs: STOMPFrame) -> Bool {
        lhs.head == rhs.head
    }
    
    public var head: STOMPFrameHead
    public var body: Data = Data()
}

public typealias STOMPFramePart = STOMPPart<STOMPFrameHead, NIO.ByteBuffer>
