// Mouse/Services/DiscoveryService.swift
import Network
import Foundation

private let kDiscoveryPort: UInt16 = 5051

enum DiscoveryState: Equatable {
    case searching
    /// Browser is waiting — usually means Local Network permission is denied.
    case permissionDenied
    case failed(String)
}

/// Discovers Mouse servers two ways:
///   1. Bonjour/mDNS via NWBrowser (works on most home networks)
///   2. UDP broadcast on port 5051 (fallback when mDNS multicast is blocked)
/// Results and state changes are delivered on the main queue.
final class DiscoveryService {
    var onServersChanged: (([ServerConfig]) -> Void)?
    var onStateChanged: ((DiscoveryState) -> Void)?

    private var browser: NWBrowser?
    private var bonjourServers: [ServerConfig] = []
    // Keyed by host string so repeated broadcasts from the same server stay stable.
    private var broadcastServers: [String: ServerConfig] = [:]

    // POSIX socket for broadcast reception — avoids NWListener rebind issues on reconnect.
    private var broadcastFd: Int32 = -1
    private let broadcastQueue = DispatchQueue(label: "mouse.discovery.broadcast", qos: .utility)

    func start() {
        startBonjour()
        startBroadcastListener()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        stopBroadcastListener()
        bonjourServers = []
        broadcastServers = [:]
    }

    // MARK: - Bonjour

    private func startBonjour() {
        browser?.cancel()
        let params = NWParameters()
        params.includePeerToPeer = false

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_mouse._udp.", domain: "local."),
            using: params
        )

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.onStateChanged?(.searching)
                case .waiting:
                    self?.onStateChanged?(.permissionDenied)
                case .failed(let error):
                    self?.onStateChanged?(.failed(error.localizedDescription))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.startBonjour() }
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let servers: [ServerConfig] = results.compactMap { result in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return .bonjour(name: name)
            }
            DispatchQueue.main.async {
                self.bonjourServers = servers
                self.notifyChanged()
            }
        }

        browser?.start(queue: .main)
    }

    // MARK: - UDP Broadcast fallback (POSIX socket)

    private func startBroadcastListener() {
        stopBroadcastListener()

        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return }

        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = kDiscoveryPort.bigEndian
        addr.sin_addr.s_addr = 0  // INADDR_ANY

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(sock); return }

        broadcastFd = sock
        broadcastQueue.async { [weak self] in
            self?.receiveLoop(fd: sock)
        }
    }

    private func stopBroadcastListener() {
        let fd = broadcastFd
        broadcastFd = -1
        if fd >= 0 { close(fd) }  // unblocks recvfrom on the background thread
    }

    private func receiveLoop(fd: Int32) {
        var buf = Data(count: 4096)
        var src = sockaddr_in()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while true {
            let n = buf.withUnsafeMutableBytes { bufPtr in
                withUnsafeMutablePointer(to: &src) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, bufPtr.baseAddress, bufPtr.count, 0, $0, &srcLen)
                    }
                }
            }
            guard n > 0 else { return }

            let packet = Data(buf.prefix(n))
            let ipStr = String(cString: inet_ntoa(src.sin_addr))

            DispatchQueue.main.async { [weak self] in
                self?.handleBroadcast(data: packet, ip: ipStr)
            }
        }
    }

    private func handleBroadcast(data: Data, ip: String) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["type"] as? String == "discover",
            let port = json["port"] as? Int,
            let name = json["name"] as? String
        else { return }

        let config = ServerConfig.broadcast(name: name, host: ip, port: UInt16(port))
        broadcastServers[ip] = config
        notifyChanged()
    }

    // MARK: - Merge and notify

    private func notifyChanged() {
        // Bonjour results take priority; broadcast fills in for hosts not already listed.
        let bonjourHosts = Set(bonjourServers.compactMap(\.host))
        let broadcastOnly = broadcastServers.values.filter { !bonjourHosts.contains($0.host ?? "") }
        let merged = bonjourServers + broadcastOnly
        onServersChanged?(merged)
    }
}
