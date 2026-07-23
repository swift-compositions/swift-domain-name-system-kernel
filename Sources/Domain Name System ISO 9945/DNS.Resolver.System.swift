// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-domain-name-system-iso-9945 open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-domain-name-system-iso-9945 project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import Domain_Name_System
internal import Either_Primitives
public import ISO_9945_Kernel_Socket_Address
public import Thread_Pool

extension DNS.Resolver {
    /// The system resolver: typed POSIX host resolution on a shared bounded
    /// worker pool.
    ///
    /// Resolution runs `getaddrinfo` through the typed ISO 9945 surface, so
    /// the platform's complete policy applies — `/etc/hosts`, NSS, search
    /// domains, split DNS, and enterprise configuration. No public resolver
    /// is hard-coded, no time-to-live is invented, and results keep the
    /// system resolver's order.
    ///
    /// ## Lifecycle
    ///
    /// The blocking OS call is uninterruptible, so it executes as
    /// abandonment-safe work on an externally owned `Kernel.Thread.Pool`.
    /// Cancellation, timeout, or pool shutdown resumes the logical requester
    /// promptly and marks the work abandoned; the admitted worker keeps
    /// exclusive ownership of the `addrinfo` chain and frees it when the OS
    /// call finishes, whether or not anyone is still waiting. When the
    /// bounded admission queue is full, resolution fails with
    /// ``Error-swift.enum/capacity`` instead of creating another thread.
    ///
    /// This resolver never shuts the pool down; only the pool's owner may.
    public struct System: Sendable {
        /// The externally owned pool executing uninterruptible resolution calls.
        private let pool: Kernel.Thread.Pool

        /// Creates a system resolver over an externally owned worker pool.
        ///
        /// - Parameter pool: The bounded pool that executes the blocking OS
        ///   calls. The resolver borrows it and never shuts it down.
        public init(pool: Kernel.Thread.Pool = .shared) {
            self.pool = pool
        }
    }
}

// MARK: - DNS.Resolving

extension DNS.Resolver.System: DNS.Resolving {
    /// Resolves one query through the system resolver.
    ///
    /// - Parameter query: The validated question.
    /// - Returns: Canonical addresses in the system resolver's order.
    /// - Throws: ``Error-swift.enum`` — pool lifecycle outcomes or the typed
    ///   `EAI_*` resolution failure.
    public func resolve(_ query: DNS.Query) async throws(Error) -> [IP.Address] {
        let host = query.name.description
        let hints = Self.hints(for: query.family)
        do throws(Either<Kernel.Thread.Pool.Error, ISO_9945.Kernel.Socket.Address.Info.Error>) {
            return try await pool.run(timeout: query.timeout) {
                () throws(ISO_9945.Kernel.Socket.Address.Info.Error) -> [IP.Address] in
                let list = try ISO_9945.Kernel.Socket.Address.Info.List.get(host: host, hints: hints)
                return Self.addresses(of: list.entries)
            }
        } catch {
            throw Error(from: error)
        }
    }
}

// MARK: - Query Translation

extension DNS.Resolver.System {
    /// Maps the family preference onto typed resolution hints.
    ///
    /// The stream socket type collapses the per-socket-type duplicates
    /// `getaddrinfo` would otherwise return, without reordering addresses.
    private static func hints(
        for family: DNS.Query.Family
    ) -> ISO_9945.Kernel.Socket.Address.Info.Hints {
        .init(
            family: Self.family(for: family),
            kind: .stream
        )
    }

    /// Maps the provider-neutral family preference onto the typed constant.
    private static func family(
        for family: DNS.Query.Family
    ) -> ISO_9945.Kernel.Socket.Address.Family {
        switch family {
        case .any: .unspecified
        case .v4: .inet
        case .v6: .inet6
        }
    }

    /// Converts owned entries into canonical addresses, preserving order.
    private static func addresses(
        of entries: [ISO_9945.Kernel.Socket.Address.Info]
    ) -> [IP.Address] {
        entries.compactMap { entry in
            if let v4 = entry.address.ipv4 {
                return .v4(IPv4.Address(rawValue: UInt32(bigEndian: v4.address)))
            }
            if let v6 = entry.address.ipv6 {
                let segments = v6.segments
                return .v6(
                    IPv6.Address(
                        segments.0, segments.1, segments.2, segments.3,
                        segments.4, segments.5, segments.6, segments.7
                    )
                )
            }
            return nil
        }
    }
}
