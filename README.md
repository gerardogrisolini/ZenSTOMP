# ZenSTOMP

### Getting Started

#### Adding a dependencies clause to your Package.swift

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenSTOMP.git", from: "1.0.6")
]
```

#### Make client
```
import NIO
import ZenSTOMP

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
defer { try! eventLoopGroup.syncShutdownGracefully() }

let stomp = ZenSTOMP(host: "www.stompserver.org", port: 61716, reconnect: false, eventLoopGroup: eventLoopGroup)
try stomp.addTLS(cert: "certificate.crt", key: "private.key")
stomp.addKeepAlive(seconds: 10, destination: "/alive", message: "IoT Gateway is alive")

stomp.onMessageReceived = { message in
    print(message.head)
}

stomp.onHandlerRemoved = {
    print("Handler removed")
}

stomp.onErrorCaught = { error in
    print(error.localizedDescription)
}
```

#### Connect to server
```
try stomp.connect(username: "test", password: "test").wait()
```

#### Subscibe destination
```
try stomp.subscribe(id: "1", destination: "/topic/test", ack: .client).wait()
```

#### Send message
```
let payload = "IoT send message test".data(using: .utf8)!
try stomp.send(destination: "/topic/test", payload: payload).wait()
```

#### Unsubscibe destination
```
try stomp.unsubscribe(id: "1").wait()
```

#### Disconnect client
```
try stomp.disconnect().wait()
```
