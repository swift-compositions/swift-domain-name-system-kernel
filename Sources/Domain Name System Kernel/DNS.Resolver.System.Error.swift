public import Domain_Name_System
internal import Either_Primitives
public import Kernel
internal import Thread_Pool

extension DNS.Resolver.System {

    public enum Error: Swift.Error, Sendable, Equatable {

        case capacity

        case cancelled

        case timeout

        case shutdown

        case resolution(Kernel.Socket.Address.Info.Error)
    }
}

extension DNS.Resolver.System.Error {

    internal init(
        from error: Either<Kernel.Thread.Pool.Error, Kernel.Socket.Address.Info.Error>
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
