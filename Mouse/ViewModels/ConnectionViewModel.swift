// Mouse/ViewModels/ConnectionViewModel.swift
import Foundation

private let lastServerDefaultsKey = "lastConnectedServer"

/// Manages the full connection lifecycle:
/// - Starts Bonjour discovery on launch (or auto-reconnects to last server)
/// - Exposes discoveredServers for ServerPickerView
/// - Owns NetworkService (passed down to TrackpadViewModel when connected)
@Observable
final class ConnectionViewModel {
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var discoveredServers: [ServerConfig] = []
    private(set) var connectionError: String?

    let networkService = NetworkService()
    private let discoveryService = DiscoveryService()

    init() {
        discoveryService.onServersChanged = { [weak self] servers in
            self?.discoveredServers = servers
        }
        attemptAutoReconnect()
    }

    // MARK: - Public

    func connect(to config: ServerConfig) {
        discoveryService.stop()
        discoveredServers = []
        connectionState = .connecting
        connectionError = nil

        networkService.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                connectionState = .connected
                saveLastServer(config)
            case .failed(let error):
                connectionState = .error(error.localizedDescription)
                connectionError = error.localizedDescription
                startDiscovery()
            case .cancelled:
                // Only restart discovery if we weren't the ones cancelling intentionally
                if case .connecting = connectionState {
                    startDiscovery()
                }
            default:
                break
            }
        }

        networkService.connect(to: config)
    }

    func disconnect() {
        networkService.onStateChange = nil
        networkService.disconnect()
        connectionState = .disconnected
        startDiscovery()
    }

    // MARK: - Private

    private func attemptAutoReconnect() {
        startDiscovery()
    }

    private func startDiscovery() {
        connectionState = .discovering
        discoveryService.start()
    }

    private func saveLastServer(_ config: ServerConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: lastServerDefaultsKey)
    }
}
