// Mouse/Models/MouseEvent.swift
import Foundation

enum MouseEvent: Encodable {
    case move(dx: Double, dy: Double)
    /// Encodes as "click" (not "leftClick") — matches the existing Mac server wire protocol.
    case leftClick
    case rightClick
    case scroll(dx: Double, dy: Double)

    private enum CodingKeys: String, CodingKey {
        case type, dx, dy
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .move(let dx, let dy):
            try container.encode("move", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        case .leftClick:
            try container.encode("click", forKey: .type)
        case .rightClick:
            try container.encode("rightClick", forKey: .type)
        case .scroll(let dx, let dy):
            try container.encode("scroll", forKey: .type)
            try container.encode(dx, forKey: .dx)
            try container.encode(dy, forKey: .dy)
        }
    }
}
