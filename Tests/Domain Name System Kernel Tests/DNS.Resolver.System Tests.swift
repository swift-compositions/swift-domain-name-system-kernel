import Domain_Name_System
import Domain_Name_System_Kernel
import IP_Address
import Kernel
import Testing
import Thread_Gate
import Thread_Pool

@Suite
struct `System Resolver Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

extension `System Resolver Tests`.Integration {
    @Test
    func `v4 preference resolves localhost to the IPv4 loopback`() async throws(DNS.Resolver
        .System.Error)
    {
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
    func `v6 preference resolves localhost to the IPv6 loopback`() async throws(DNS.Resolver
        .System.Error)
    {
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
    func `any family resolves localhost to both loopbacks`() async throws(DNS.Resolver
        .System.Error)
    {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let resolver = DNS.Resolver.System()
        let answers = try await resolver.resolve(DNS.Query(name: name))

        #expect(answers.contains(.v4(IPv4.Address(rawValue: 0x7F00_0001))))
        #expect(answers.contains(.v6(IPv6.Address(0, 0, 0, 0, 0, 0, 0, 1))))
    }

    @Test
    func `hosts seam resolution is deterministic across repetition`() async throws(DNS.Resolver
        .System.Error)
    {
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
    func `a caller supplied pool serves the resolver`() async throws(DNS.Resolver
        .System.Error)
    {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(.init(workers: .init(2)))
        let resolver = DNS.Resolver.System(pool: pool)
        let answers = try await resolver.resolve(DNS.Query(name: name, family: .v4))

        #expect(answers.contains(.v4(IPv4.Address(rawValue: 0x7F00_0001))))
        pool.shutdown()
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

extension `System Resolver Lifecycle Tests`.Integration {
    @Test
    func `cancellation before admission abandons the queued request promptly`() async {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(1)))
        )
        let started = Kernel.Thread.Gate()
        let release = Kernel.Thread.Gate()
        let occupant = Task { () async throws(Kernel.Thread.Pool.Error) -> Bool in
            try await pool.run {
                started.open()
                release.wait()
                return true
            }
        }
        #expect(started.wait(timeout: .seconds(5)))

        let resolver = DNS.Resolver.System(pool: pool)
        let query = DNS.Query(name: name, family: .v4)
        let waiter = Task { () async throws(DNS.Resolver.System.Error) -> [IP.Address] in
            try await resolver.resolve(query)
        }
        waiter.cancel()

        let outcome = await waiter.result
        #expect(outcome == .failure(.cancelled))

        release.open()
        let occupancy = await occupant.result
        #expect(occupancy == .success(true))
        pool.shutdown()
    }

    @Test
    func `cancellation during resolution returns promptly without claiming interruption`() async {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(2)), queued: .init(UInt(2)))
        )
        let resolver = DNS.Resolver.System(pool: pool)
        let query = DNS.Query(name: name)

        let clock = ContinuousClock()
        let started = clock.now
        let waiter = Task { () async throws(DNS.Resolver.System.Error) -> [IP.Address] in
            try await resolver.resolve(query)
        }
        waiter.cancel()

        switch await waiter.result {
        case .success:
            ()

        case .failure(let error):
            #expect(error == .cancelled)
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
        let query = DNS.Query(name: name)

        for _ in 0..<16 {
            let waiter = Task { () async throws(DNS.Resolver.System.Error) -> [IP.Address] in
                try await resolver.resolve(query)
            }
            waiter.cancel()

            _ = await waiter.result
        }

        pool.shutdown()
    }

    @Test
    func `full admission queue fails with the typed capacity error`() async {
        guard let name = `System Resolver Tests`.valid("localhost") else { return }
        let pool = Kernel.Thread.Pool(
            .init(workers: .init(1), admitted: .init(UInt(1)), queued: .init(UInt(0)))
        )
        let started = Kernel.Thread.Gate()
        let release = Kernel.Thread.Gate()
        let occupant = Task { () async throws(Kernel.Thread.Pool.Error) -> Bool in
            try await pool.run {
                started.open()
                release.wait()
                return true
            }
        }
        #expect(started.wait(timeout: .seconds(5)))

        let resolver = DNS.Resolver.System(pool: pool)
        let query = DNS.Query(name: name, family: .v4)
        do throws(DNS.Resolver.System.Error) {
            _ = try await resolver.resolve(query)
            Issue.record("Expected the typed capacity error")
        } catch {
            #expect(error == .capacity)
        }

        release.open()
        let occupancy = await occupant.result
        #expect(occupancy == .success(true))
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
