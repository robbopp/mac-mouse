// Mouse/Models/ConnectionState.swift

enum ConnectionState {
    case discovering
    case connecting
    case connected
    case disconnected
    case error(String)
}
