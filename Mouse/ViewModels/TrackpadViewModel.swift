// Mouse/ViewModels/TrackpadViewModel.swift
import Foundation
import CoreGraphics

/// Accumulates gesture deltas and flushes them at 60fps via NetworkService.
/// Tap/drag disambiguation is handled by UIGestureRecognizer in TrackpadView —
/// onLeftClick and onRightClick are only called on genuine taps.
@Observable
final class TrackpadViewModel {
    private let networkService: NetworkService
    private var pendingMoveDelta: CGPoint = .zero
    private var pendingScrollDelta: CGPoint = .zero
    private var flushTimer: Timer?

    /// Applied to move deltas before sending. Matches original 4x value.
    private let moveSensitivity: Double = 4.0

    init(networkService: NetworkService) {
        self.networkService = networkService
        flushTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }

    deinit {
        flushTimer?.invalidate()
    }

    private func flush() {
        if pendingMoveDelta != .zero {
            networkService.send(.move(
                dx: Double(pendingMoveDelta.x) * moveSensitivity,
                dy: Double(pendingMoveDelta.y) * moveSensitivity
            ))
            pendingMoveDelta = .zero
        }
        if pendingScrollDelta != .zero {
            networkService.send(.scroll(
                dx: Double(pendingScrollDelta.x),
                dy: Double(pendingScrollDelta.y)
            ))
            pendingScrollDelta = .zero
        }
    }

    // MARK: - Gesture handlers (called from TrackpadView)

    func onMoveDelta(dx: Double, dy: Double) {
        pendingMoveDelta.x += dx
        pendingMoveDelta.y += dy
    }

    func onScrollDelta(dx: Double, dy: Double) {
        pendingScrollDelta.x += dx
        pendingScrollDelta.y += dy
    }

    func onLeftClick() {
        networkService.send(.leftClick)
    }

    func onRightClick() {
        networkService.send(.rightClick)
    }
}
