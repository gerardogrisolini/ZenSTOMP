# ZenSTOMP

### Getting Started

#### Adding a dependencies clause to your Package.swift

```
dependencies: [
    .package(url: "https://github.com/gerardogrisolini/ZenSTOMP.git", from: "1.0.0")
]
```

#### Make client
```
import ZenSTOMP

let stomp = ZenSTOMP(host: "www.stompserver.org", port: 61716)
try stomp.addTLS(cert: "certificate.crt", key: "private.key")
stomp.onResponse = { response in
    print(response)
}
```

#### Start client
```
try stomp.start().wait()
```

#### Connect to server
```
try stomp.connect(username: "admin", password: "123456789").wait()
```

#### Subscibe topic
```
try stomp.subscribe(id: "1", destination: "/topic/test").wait()
```

#### Unsubscibe topic
```
try stomp.unsubscribe(id: "1").wait()
```

#### Send message
```
try stomp.send(destination: "/topic/alive", payload: "IoT Gateway is alive".data(using: .utf8)!, receipt: "ALIVE").wait()
```

#### Disconnect client
```
try stomp.disconnect().wait()
```

#### Stop client
```
try stomp.stop().wait()
```
