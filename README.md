# ZenSTOMP

### Getting Started

#### Add dependency to `Package.swift`

```swift
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenSTOMP.git", from: "1.0.6")
]
```

#### Create client

```swift
import NIO
import ZenSTOMP

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
defer { try! eventLoopGroup.syncShutdownGracefully() }

let stomp = ZenSTOMP(
    eventLoopGroup: eventLoopGroup,
    host: "your-broker-host",
    port: 61613,
    reconnect: false
)

// Set STOMP virtual host when required by broker (e.g. RabbitMQ vhost)
stomp.virtualHost = "your-vhost"

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

#### TLS options

Server certificate validation (recommended):

```swift
try stomp.enableTLS()
```

Mutual TLS (client certificate + key):

```swift
try stomp.addTLS(cert: "client.crt", key: "client.key")
```

#### Connect

```swift
try await stomp.connect(username: "test", password: "test")
```

#### Subscribe

```swift
try await stomp.subscribe(id: "1", destination: "/topic/test", ack: .client)
```

#### Send

```swift
let payload = "IoT send message test".data(using: .utf8)!
try await stomp.send(destination: "/topic/test", payload: payload)
```

#### Unsubscribe

```swift
try await stomp.unsubscribe(id: "1")
```

#### Disconnect

```swift
try await stomp.disconnect()
```

#### Compatibility wrappers (`EventLoopFuture`)

```swift
try stomp.connectFuture(username: "test", password: "test").wait()
```

#### Connectivity smoke test

Use `scripts/stomp-smoke.sh` to validate STOMP handshake (`CONNECT` -> `CONNECTED`).

```bash
STOMP_HOST=<host> STOMP_PORT=61613 STOMP_LOGIN=<user> STOMP_PASSCODE=<pass> ./scripts/stomp-smoke.sh
```

Full guide: `docs/CONNECTIVITY_TEST.md`
