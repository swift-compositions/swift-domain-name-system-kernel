# swift-domain-name-system-kernel

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

System DNS provider for swift-domain-name-system — `DNS.Resolver.System` answers `DNS.Query` values through the unified `Kernel.Socket.Address.Info` host resolution surface (`getaddrinfo`) on a bounded worker pool.

---

## Quick Start

Resolve a validated domain name with the platform's own resolution policy — `/etc/hosts`, NSS, search domains, split DNS, and enterprise configuration all apply, and results keep the system resolver's order:

```swift
import Domain_Name_System_Kernel

let resolver = DNS.Resolver.System()

let addresses = try await resolver.resolve(
    DNS.Query(
        name: try RFC_1035.Domain("example.com"),
        family: .any,
        timeout: .seconds(5)
    )
)
// [IP.Address] in the system resolver's order — no family racing, no invented TTL.
```

The blocking OS call runs as abandonment-safe work on an externally owned `Kernel.Thread.Pool`. Cancellation and timeout resume the caller promptly and abandon delivery — they never claim to interrupt the OS call; the admitted worker keeps ownership of its `addrinfo` chain and frees it when the call finishes. A full admission queue fails with a typed `.capacity` error rather than creating another thread:

```swift
import Domain_Name_System_Kernel

// Inject a pool the application owns; the resolver never shuts it down.
let pool = Kernel.Thread.Pool(.init(admitted: .init(UInt(64)), queued: .init(UInt(64))))
let resolver = DNS.Resolver.System(pool: pool)
```

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-domain-name-system-kernel.git", branch: "main")
]
```

Then add the product to your target:

```swift
.product(name: "Domain Name System Kernel", package: "swift-domain-name-system-kernel")
```

## Scope

This package is the system adapter only. The provider-neutral resolver seam lives in [swift-domain-name-system](https://github.com/swift-foundations/swift-domain-name-system); DNS wire records and message law live with RFC 1035. No wire resolver, cache, or TTL policy is implemented here.

## License

Apache License v2.0 — see [LICENSE](LICENSE.md).
