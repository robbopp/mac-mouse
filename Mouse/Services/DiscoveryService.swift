// Mouse/Services/DiscoveryService.swift
import Network
import Foundation

private let kDiscoveryPort: NWEndpoint.Port = 5051

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
    private var broadcastListener: NWListener?
    private var bonjourServers: [ServerConfig] = []
    // Keyed by host string so repeated broadcasts from the same server stay stable.
    private var broadcastServers: [String: ServerConfig] = [:]

    func start() {
        startBonjour()
        startBroadcastListener()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        broadcastListener?.cancel()
        broadcastListener = nil
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

    // MARK: - UDP Broadcast fallback

    private func startBroadcastListener() {
        broadcastListener?.cancel()
        guard let listener = try? NWListener(using: .udp, on: kDiscoveryPort) else { return }

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            self?.receiveAnnouncement(from: connection)
        }
        listener.start(queue: .main)
        broadcastListener = listener
    }

    private func receiveAnnouncement(from connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, _ in
            guard let self, let data else { return }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["type"] as? String == "discover",
                let port = json["port"] as? Int,
                let name = json["name"] as? String,
                case .hostPort(let host, _) = connection.endpoint
            else { return }

            // Strip IPv6-mapped IPv4 prefix ("::ffff:192.168.1.x" → "192.168.1.x")
            var hostStr = "\(host)"
            if hostStr.hasPrefix("::ffff:") { hostStr = String(hostStr.dropFirst(7)) }

            let config = ServerConfig.broadcast(name: name, host: hostStr, port: UInt16(port))
            self.broadcastServers[hostStr] = config
            self.notifyChanged()
        }
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
