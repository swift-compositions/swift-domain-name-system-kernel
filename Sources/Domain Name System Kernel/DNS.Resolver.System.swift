public import Domain_Name_System
internal import Either
public import Kernel
public import Thread_Pool

extension DNS.Resolver {

    public struct System: Sendable {

        private let pool: Kernel.Thread.Pool

        public init(pool: Kernel.Thread.Pool = .shared) {
            self.pool = pool
        }
    }
}

extension DNS.Resolver.System: DNS.Resolving {

    public func resolve(_ query: DNS.Query) async throws(Error) -> [IP.Address] {
        let host = query.name.description
        let hints = Self.hints(for: query.family)
        do throws(Either<Kernel.Thread.Pool.Error, Kernel.Socket.Address.Info.Error>) {
            return try await pool.run(timeout: query.timeout) {
                () throws(Kernel.Socket.Address.Info.Error) -> [IP.Address] in
                let list = try Kernel.Socket.Address.Info.List.get(host: host, hints: hints)
                return Self.addresses(of: list.entries)
            }
        } catch {
            throw Error(from: error)
        }
    }
}

extension DNS.Resolver.System {

    private static func hints(
        for family: DNS.Query.Family
    ) -> Kernel.Socket.Address.Info.Hints {
        .init(
            family: Self.family(for: family),
            kind: .stream
        )
    }

    private static func family(
        for family: DNS.Query.Family
    ) -> Kernel.Socket.Address.Family {
        switch family {
        case .any: .unspecified
        case .v4: .inet
        case .v6: .inet6
        }
    }

    private static func addresses(
        of entries: [Kernel.Socket.Address.Info]
    ) -> [IP.Address] {
        entries.compactMap { entry in
            if let v4 = entry.address.ipv4 {
                return .v4(IPv4.Address(rawValue: UInt32(bigEndian: v4.address)))
            }
            if let v6 = entry.address.ipv6 {
                let segments = v6.segments
                return .v6(
                    IPv6.Address(
                        segments.0,
                        segments.1,
                        segments.2,
                        segments.3,
                        segments.4,
                        segments.5,
                        segments.6,
                        segments.7
                    )
                )
            }
            return nil
        }
    }
}
