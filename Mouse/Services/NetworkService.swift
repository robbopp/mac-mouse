// Mouse/Services/NetworkService.swift
import Network
import Foundation

/// Owns a single UDP NWConnection. Sends MouseEvents as JSON.
/// Call connect(to:) to establish or re-establish the connection.
/// Set onStateChange to be notified of state transitions.
final class NetworkService {
    /// Called on the main queue whenever the underlying NWConnection state changes.
    var onStateChange: ((NWConnection.State) -> Void)?

    private var connection: NWConnection?

    func connect(to config: ServerConfig) {
        connection?.cancel()

        let endpoint: NWEndpoint
        if let bonjourName = config.bonjourName {
            endpoint = .service(
                name: bonjourName,
                type: "_mouse._udp.",
                domain: "local.",
                interface: nil
            )
        } else if let host = config.host, let port = NWEndpoint.Port(rawValue: config.port) {
            endpoint = .hostPort(host: NWEndpoint.Host(host), port: port)
        } else {
            return
        }

        let params = NWParameters.udp
        connection = NWConnection(to: endpoint, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.onStateChange?(state)
            }
        }
        connection?.start(queue: .main)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ event: MouseEvent) {
        guard let connection, let data = try? JSONEncoder().encode(event) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
