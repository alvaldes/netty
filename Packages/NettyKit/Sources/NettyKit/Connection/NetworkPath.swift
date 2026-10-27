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
    /// A VPN tunnel carries the traffic (heuristic: the preferred interface is a tunnel).
    /// Split-tunnel VPNs that leave the default route alone are not detected.
    public var isVPN: Bool

    public init(isSatisfied: Bool, interface: Interface, isExpensive: Bool, isConstrained: Bool, isVPN: Bool = false) {
        self.isSatisfied = isSatisfied
        self.interface = interface
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.isVPN = isVPN
    }

    static func isTunnel(interfaceName name: String) -> Bool {
        ["utun", "ipsec", "ppp"].contains { prefix in
            name.hasPrefix(prefix) && name.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }
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
        isVPN = path.status == .satisfied && path.availableInterfaces.first.map { Self.isTunnel(interfaceName: $0.name) } == true
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
