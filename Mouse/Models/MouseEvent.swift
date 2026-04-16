// Mouse/Models/MouseEvent.swift
import Foundation

enum MouseEvent: Encodable {
    case move(dx: Double, dy: Double)
    /// Encodes as "click" (not "leftClick") — matches the existing Mac server wire protocol.
    case leftClick
    case rightClick
    case scroll(dx: Double, dy: Double)
    case swipeLeft   // 3-finger → switch space left  (Ctrl+←)
    case swipeRight  // 3-finger → switch space right (Ctrl+→)
    case swipeUp     // 3-finger → Mission Control    (Ctrl+↑)
    case swipeDown   // 3-finger → App Exposé         (Ctrl+↓)

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
        case .swipeLeft:
            try container.encode("swipeLeft", forKey: .type)
        case .swipeRight:
            try container.encode("swipeRight", forKey: .type)
        case .swipeUp:
            try container.encode("swipeUp", forKey: .type)
        case .swipeDown:
            try container.encode("swipeDown", forKey: .type)
        }
    }
}
