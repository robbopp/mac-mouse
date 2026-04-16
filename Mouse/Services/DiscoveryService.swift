// Mouse/Services/DiscoveryService.swift
import Network
import Foundation

/// Browses for _mouse._udp. Bonjour services on the local network.
/// Results are delivered to onServersChanged on the main queue.
final class DiscoveryService {
    var onServersChanged: (([ServerConfig]) -> Void)?
    private var browser: NWBrowser?

    func start() {
        let params = NWParameters()
        params.includePeerToPeer = false

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_mouse._udp.", domain: "local."),
            using: params
        )

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            let servers: [ServerConfig] = results.compactMap { result in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return .bonjour(name: name)
            }
            DispatchQueue.main.async {
                self?.onServersChanged?(servers)
            }
        }

        browser?.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
