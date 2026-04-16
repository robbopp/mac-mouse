// Mouse/Models/ConnectionState.swift

enum ConnectionState: Equatable {
    case discovering
    case connecting
    case connected
    case disconnected
    case error(String)
}
