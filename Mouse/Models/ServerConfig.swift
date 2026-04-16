// Mouse/Models/ServerConfig.swift
import Foundation

struct ServerConfig: Identifiable, Hashable, Codable {
    let id: UUID
    let displayName: String
    /// Set for Bonjour-discovered servers. Used to build NWEndpoint.service.
    let bonjourName: String?
    /// Set for manually-entered servers.
    let host: String?
    let port: UInt16

    static func bonjour(name: String) -> ServerConfig {
        ServerConfig(id: UUID(), displayName: name, bonjourName: name, host: nil, port: 5050)
    }

    static func manual(host: String, port: UInt16) -> ServerConfig {
        ServerConfig(id: UUID(), displayName: "\(host):\(port)", bonjourName: nil, host: host, port: port)
    }
}
