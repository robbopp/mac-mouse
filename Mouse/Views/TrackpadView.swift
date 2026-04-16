// Mouse/Views/TrackpadView.swift
import SwiftUI
import UIKit

// MARK: - Root SwiftUI View

struct TrackpadView: View {
    @State private var viewModel: TrackpadViewModel
    let onDisconnect: () -> Void

    init(networkService: NetworkService, onDisconnect: @escaping () -> Void) {
        _viewModel = State(initialValue: TrackpadViewModel(networkService: networkService))
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GestureView(
                onMoveDelta: { dx, dy in viewModel.onMoveDelta(dx: dx, dy: dy) },
                onScrollDelta: { dx, dy in viewModel.onScrollDelta(dx: dx, dy: dy) },
                onLeftClick: { viewModel.onLeftClick() },
                onRightClick: { viewModel.onRightClick() }
            )
            .ignoresSafeArea()

            ToolbarView(
                onRightClick: { viewModel.onRightClick() },
                onDisconnect: onDisconnect
            )
        }
    }
}

// MARK: - UIViewRepresentable gesture surface

private struct GestureView: UIViewRepresentable {
    var onMoveDelta: (Double, Double) -> Void
    var onScrollDelta: (Double, Double) -> Void
    var onLeftClick: () -> Void
    var onRightClick: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true

        // 1-finger pan → cursor move
        let movePan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMovePan(_:))
        )
        movePan.minimumNumberOfTouches = 1
        movePan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(movePan)

        // 2-finger pan → scroll
        let scrollPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleScrollPan(_:))
        )
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(scrollPan)

        // 1-finger tap → left click
        // UITapGestureRecognizer only fires when there is no significant movement,
        // so it naturally does not conflict with the 1-finger pan.
        let leftTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLeftTap)
        )
        leftTap.numberOfTouchesRequired = 1
        leftTap.numberOfTapsRequired = 1
        view.addGestureRecognizer(leftTap)

        // 2-finger tap → right click
        let rightTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleRightTap)
        )
        rightTap.numberOfTouchesRequired = 2
        rightTap.numberOfTapsRequired = 1
        view.addGestureRecognizer(rightTap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Keep coordinator callbacks up to date when the view re-renders
        context.coordinator.onMoveDelta = onMoveDelta
        context.coordinator.onScrollDelta = onScrollDelta
        context.coordinator.onLeftClick = onLeftClick
        context.coordinator.onRightClick = onRightClick
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMoveDelta: onMoveDelta,
            onScrollDelta: onScrollDelta,
            onLeftClick: onLeftClick,
            onRightClick: onRightClick
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var onMoveDelta: (Double, Double) -> Void
        var onScrollDelta: (Double, Double) -> Void
        var onLeftClick: () -> Void
        var onRightClick: () -> Void

        private var lastMoveLocation: CGPoint?
        private var lastScrollLocation: CGPoint?

        init(
            onMoveDelta: @escaping (Double, Double) -> Void,
            onScrollDelta: @escaping (Double, Double) -> Void,
            onLeftClick: @escaping () -> Void,
            onRightClick: @escaping () -> Void
        ) {
            self.onMoveDelta = onMoveDelta
            self.onScrollDelta = onScrollDelta
            self.onLeftClick = onLeftClick
            self.onRightClick = onRightClick
        }

        @objc func handleMovePan(_ recognizer: UIPanGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began:
                lastMoveLocation = location
            case .changed:
                if let last = lastMoveLocation {
                    onMoveDelta(location.x - last.x, location.y - last.y)
                }
                lastMoveLocation = location
            case .ended, .cancelled, .failed:
                lastMoveLocation = nil
            default:
                break
            }
        }

        @objc func handleScrollPan(_ recognizer: UIPanGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began:
                lastScrollLocation = location
            case .changed:
                if let last = lastScrollLocation {
                    onScrollDelta(location.x - last.x, location.y - last.y)
                }
                lastScrollLocation = location
            case .ended, .cancelled, .failed:
                lastScrollLocation = nil
            default:
                break
            }
        }

        @objc func handleLeftTap() {
            onLeftClick()
        }

        @objc func handleRightTap() {
            onRightClick()
        }
    }
}
