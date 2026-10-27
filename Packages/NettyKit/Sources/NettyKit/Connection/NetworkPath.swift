import Network

/// What the system reports about the current network path.
nonisolated public struct NetworkPath: Sendable, Equatable {
    public enum Interface: Sendable, Equatable {
        case wifi, ethernet, cellular, other, none
    }

    /// A route exists. Not proof of internet: probes decide that.
    public var isSatisfied: Bool
    public var interface: Interface
    /// Metered, e.g. an iPhone hotspot.
    public var isExpensive: Bool
    /// Low Data Mode.
    public var isConstrained: Bool

    public init(isSatisfied: Bool, interface: Interface, isExpensive: Bool, isConstrained: Bool) {
        self.isSatisfied = isSatisfied
        self.interface = interface
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }

    init(_ path: NWPath) {
        isSatisfied = path.status == .satisfied
        interface = if path.usesInterfaceType(.wifi) {
            .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            .ethernet
        } else if path.usesInterfaceType(.cellular) {
            .cellular
        } else if path.status == .satisfied {
            .other
        } else {
            .none
        }
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
    }

    /// Every path change for as long as the stream is iterated.
    static func updates() -> AsyncStream<NetworkPath> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield(NetworkPath($0)) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "Netty.NetworkPath"))
        }
    }
}
