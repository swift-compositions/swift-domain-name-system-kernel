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
internal import Thread_Pool

extension DNS.Resolver.System {
    /// System-resolution failures.
    ///
    /// Pool lifecycle outcomes cover the logical request: they report that
    /// delivery was abandoned or refused, never that the OS call itself was
    /// interrupted. ``resolution(_:)`` carries the typed `EAI_*` failure the
    /// system resolver reported.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The bounded pool refused admission; no extra thread is created.
        case capacity

        /// The logical request was cancelled and delivery abandoned.
        case cancelled

        /// The monotonic budget expired and delivery was abandoned.
        case timeout

        /// The pool was shut down by its owner.
        case shutdown

        /// The system resolver failed with the typed `EAI_*` error.
        case resolution(ISO_9945.Kernel.Socket.Address.Info.Error)
    }
}

// MARK: - Mapping

extension DNS.Resolver.System.Error {
    /// Maps the pool-or-resolution failure onto this domain.
    internal init(
        from error: Either<Kernel.Thread.Pool.Error, ISO_9945.Kernel.Socket.Address.Info.Error>
    ) {
        switch error {
        case .left(let pool):
            switch pool {
            case .capacity: self = .capacity
            case .cancelled: self = .cancelled
            case .timeout: self = .timeout
            case .shutdown: self = .shutdown
            }
        case .right(let resolution):
            self = .resolution(resolution)
        }
    }
}
