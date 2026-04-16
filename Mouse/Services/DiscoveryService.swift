// Mouse/Services/DiscoveryService.swift
import Network
import Foundation

enum DiscoveryState: Equatable {
    case searching
    /// Browser is waiting — usually means Local Network permission is denied.
    case permissionDenied
    case failed(String)
}

/// Browses for _mouse._udp. Bonjour services on the local network.
/// Results and state changes are delivered on the main queue.
final class DiscoveryService {
    var onServersChanged: (([ServerConfig]) -> Void)?
    var onStateChanged: ((DiscoveryState) -> Void)?
    private var browser: NWBrowser?

    func start() {
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
                    // .waiting almost always means Local Network permission was denied.
                    self?.onStateChanged?(.permissionDenied)
                case .failed(let error):
                    self?.onStateChanged?(.failed(error.localizedDescription))
                    // Retry after a short delay.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self?.start()
                    }
                default:
                    break
                }
            }
        }

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
