// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-domain-name-system-kernel open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-domain-name-system-kernel project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Testing
import Thread_Gate

@testable import Domain_Name_System_Kernel

@Suite
struct `System Resolver Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

extension `System Resolver Tests`.Integration {
    @Test
    func `v4 preference resolves localhost to ordered IPv4 loopback`() async throws(DNS.Resolver.System.Error) {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let resolver = DNS.Resolver.System()
        let answers = try await resolver.resolve(DNS.Query(name: name, family: .v4))

        #expect(!answers.isEmpty)
        for answer in answers {
            guard case .v4 = answer else {
                Issue.record("Expected only IPv4 answers, got \(answer)")
                return
            }
        }
        #expect(answers.contains(.v4(IPv4.Address(rawValue: 0x7F00_0001))))
    }

    @Test
    func `v6 preference resolves localhost to ordered IPv6 loopback`() async throws(DNS.Resolver.System.Error) {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let resolver = DNS.Resolver.System()
        let answers = try await resolver.resolve(DNS.Query(name: name, family: .v6))

        #expect(!answers.isEmpty)
        for answer in answers {
            guard case .v6 = answer else {
                Issue.record("Expected only IPv6 answers, got \(answer)")
                return
            }
        }
        #expect(answers.contains(.v6(IPv6.Address(0, 0, 0, 0, 0, 0, 0, 1))))
    }

    @Test
    func `hosts seam resolution is deterministic across repetition`() async throws(DNS.Resolver.System.Error) {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let resolver = DNS.Resolver.System()
        let query = DNS.Query(name: name, family: .v4)
        let first = try await resolver.resolve(query)
        for _ in 0..<8 {
            let next = try await resolver.resolve(query)
            #expect(next == first)
        }
    }

    @Test
    func `system order is preserved against the direct typed surface`() async throws(DNS.Resolver.System.Error) {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let resolver = DNS.Resolver.System()
        let adapted = try await resolver.resolve(DNS.Query(name: name, family: .any))

        do throws(Kernel.Socket.Address.Info.Error) {
            let direct = try Kernel.Socket.Address.Info.List.get(
                host: "localhost",
                hints: .init(family: .unspecified, kind: .stream)
            ).entries.compactMap { entry -> IP.Address? in
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
            #expect(adapted == direct)
        } catch {
            Issue.record("Direct typed surface unexpectedly failed: \(error)")
        }
    }
}

extension `System Resolver Tests`.`Edge Case` {
    @Test
    func `unresolvable name fails with the typed resolution error`() async {
        guard let name = `System Resolver Tests`.valid("does-not-exist.invalid") else { return }
        let resolver = DNS.Resolver.System()
        let query = DNS.Query(name: name, family: .v4)
        do throws(DNS.Resolver.System.Error) {
            _ = try await resolver.resolve(query)
            Issue.record("Expected a resolution failure for .invalid")
        } catch {
            guard case .resolution(let failure) = error else {
                Issue.record("Expected .resolution, got \(error)")
                return
            }
            #expect(failure == .noName || failure == .again || failure == .fail)
        }
    }
}

extension `System Resolver Tests` {
    /// Returns a validated domain, recording an issue on failure.
    static func valid(_ name: Swift.String) -> RFC_1035.Domain? {
        do throws(RFC_1035.Domain.Error) {
            return try RFC_1035.Domain(name)
        } catch {
            Issue.record("Domain validation unexpectedly failed: \(error)")
            return nil
        }
    }
}

@Suite
struct `System Resolver Lifecycle Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

extension `System Resolver Lifecycle Tests` {
    /// Occupies every admission slot of `pool` until the gate opens.
    ///
    /// Returns the task that owns the blocking occupant so callers can await
    /// full drain after opening the gate.
    static func occupy(
        _ pool: Kernel.Thread.Pool,
        until gate: Kernel.Thread.Gate
    ) -> Task<Void, Never> {
        Task {
            do throws(Kernel.Thread.Pool.Error) {
                try await pool.run { gate.wait() }
            } catch {
                Issue.record("Occupant unexpectedly failed: \(error)")
            }
        }
    }

    /// Yields until the occupant has actually been admitted, so a subsequent
    /// reservation deterministically sees a full pool.
    static func settle() async {
        for _ in 0..<64 { await Task.yield() }
    }
}

extension `System Resolver Lifecycle Tests`.Integration {
    @Test
    func `cancellation before admission abandons the queued request promptly`() async {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(1)))
        )
        let gate = Kernel.Thread.Gate()
        let occupant = `System Resolver Lifecycle Tests`.occupy(pool, until: gate)
        await `System Resolver Lifecycle Tests`.settle()

        let resolver = DNS.Resolver.System(pool: pool)
        let query = DNS.Query(name: name, family: .v4)
        let waiter = Task { () throws(DNS.Resolver.System.Error) -> [IP.Address] in
            try await resolver.resolve(query)
        }
        await `System Resolver Lifecycle Tests`.settle()
        waiter.cancel()

        switch await waiter.result {
        case .success:
            Issue.record("Expected cancellation of the queued request")
        case .failure(let error):
            #expect(error as? DNS.Resolver.System.Error == .cancelled)
        }

        gate.open()
        await occupant.value
        pool.shutdown()
    }

    @Test
    func `cancellation during resolution returns promptly without claiming interruption`() async {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(2)), queued: .init(UInt(2)))
        )
        let resolver = DNS.Resolver.System(pool: pool)
        let query = DNS.Query(name: name, family: .any)

        let clock = ContinuousClock()
        let started = clock.now
        let waiter = Task { () throws(DNS.Resolver.System.Error) -> [IP.Address] in
            try await resolver.resolve(query)
        }
        waiter.cancel()

        // Either outcome is legal — completion may have won the race — but
        // the logical request must resume promptly either way.
        switch await waiter.result {
        case .success:
            ()
        case .failure(let error):
            #expect(error as? DNS.Resolver.System.Error == .cancelled)
        }
        #expect(clock.now - started < .seconds(10))

        pool.shutdown()
    }

    @Test
    func `abandoned late results drain cleanly through pool shutdown`() async {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(2), admitted: .init(UInt(4)), queued: .init(UInt(4)))
        )
        let resolver = DNS.Resolver.System(pool: pool)
        let query = DNS.Query(name: name, family: .any)

        for _ in 0..<16 {
            let waiter = Task { () throws(DNS.Resolver.System.Error) -> [IP.Address] in
                try await resolver.resolve(query)
            }
            waiter.cancel()
            // Abandonment is the expected path; success means the resolution
            // won the race. Both are legal here.
            _ = await waiter.result
        }

        // Shutdown drains every admitted worker; each worker owned and freed
        // its addrinfo chain regardless of the abandoned logical requests.
        pool.shutdown()
    }

    @Test
    func `full admission queue fails with the typed capacity error`() async {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(0)))
        )
        let gate = Kernel.Thread.Gate()
        let occupant = `System Resolver Lifecycle Tests`.occupy(pool, until: gate)
        await `System Resolver Lifecycle Tests`.settle()

        let resolver = DNS.Resolver.System(pool: pool)
        let query = DNS.Query(name: name, family: .v4)
        do throws(DNS.Resolver.System.Error) {
            _ = try await resolver.resolve(query)
            Issue.record("Expected the typed capacity error")
        } catch {
            #expect(error == .capacity)
        }

        gate.open()
        await occupant.value
        pool.shutdown()
    }

    @Test
    func `resolution after owner shutdown fails with the typed shutdown error`() async {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(1)))
        )
        pool.shutdown()

        let resolver = DNS.Resolver.System(pool: pool)
        let query = DNS.Query(name: name, family: .v4)
        do throws(DNS.Resolver.System.Error) {
            _ = try await resolver.resolve(query)
            Issue.record("Expected the typed shutdown error")
        } catch {
            #expect(error == .shutdown)
        }
    }
}
