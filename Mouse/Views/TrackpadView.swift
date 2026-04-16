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
                onMoveDelta:  { dx, dy in viewModel.onMoveDelta(dx: dx, dy: dy) },
                onScrollDelta: { dx, dy in viewModel.onScrollDelta(dx: dx, dy: dy) },
                onLeftClick:  { viewModel.onLeftClick() },
                onRightClick: { viewModel.onRightClick() },
                onSwipeLeft:  { viewModel.onSwipeLeft() },
                onSwipeRight: { viewModel.onSwipeRight() },
                onSwipeUp:    { viewModel.onSwipeUp() },
                onSwipeDown:  { viewModel.onSwipeDown() }
            )
            .ignoresSafeArea()

            ToolbarView(
                onRightClick: { viewModel.onRightClick() },
                onDisconnect: onDisconnect
            )
        }
        .onAppear { requestOrientation(.landscape) }
        .onDisappear { requestOrientation(.portrait) }
    }
}

// MARK: - UIViewRepresentable gesture surface

private struct GestureView: UIViewRepresentable {
    var onMoveDelta: (Double, Double) -> Void
    var onScrollDelta: (Double, Double) -> Void
    var onLeftClick: () -> Void
    var onRightClick: () -> Void
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    var onSwipeUp: () -> Void
    var onSwipeDown: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true

        // Single pan recognizer handles both 1-finger (move) and 2-finger (scroll).
        // Using two separate recognizers caused the 1-finger one to grab the first
        // touch before the second finger could arrive, making 2-finger scroll unreliable.
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)

        // 1-finger tap → left click
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

        // 3-finger swipes → space switching / Mission Control
        for (dir, sel) in [
            (UISwipeGestureRecognizer.Direction.left,  #selector(Coordinator.handleSwipeLeft)),
            (.right, #selector(Coordinator.handleSwipeRight)),
            (.up,    #selector(Coordinator.handleSwipeUp)),
            (.down,  #selector(Coordinator.handleSwipeDown)),
        ] {
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: sel)
            swipe.numberOfTouchesRequired = 3
            swipe.direction = dir
            view.addGestureRecognizer(swipe)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onMoveDelta  = onMoveDelta
        context.coordinator.onScrollDelta = onScrollDelta
        context.coordinator.onLeftClick  = onLeftClick
        context.coordinator.onRightClick = onRightClick
        context.coordinator.onSwipeLeft  = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        context.coordinator.onSwipeUp    = onSwipeUp
        context.coordinator.onSwipeDown  = onSwipeDown
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMoveDelta: onMoveDelta,
            onScrollDelta: onScrollDelta,
            onLeftClick: onLeftClick,
            onRightClick: onRightClick,
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            onSwipeUp: onSwipeUp,
            onSwipeDown: onSwipeDown
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var onMoveDelta: (Double, Double) -> Void
        var onScrollDelta: (Double, Double) -> Void
        var onLeftClick: () -> Void
        var onRightClick: () -> Void
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        var onSwipeUp: () -> Void
        var onSwipeDown: () -> Void

        private var lastLocation: CGPoint?
        private var lastTouchCount: Int = 0

        init(
            onMoveDelta: @escaping (Double, Double) -> Void,
            onScrollDelta: @escaping (Double, Double) -> Void,
            onLeftClick: @escaping () -> Void,
            onRightClick: @escaping () -> Void,
            onSwipeLeft: @escaping () -> Void,
            onSwipeRight: @escaping () -> Void,
            onSwipeUp: @escaping () -> Void,
            onSwipeDown: @escaping () -> Void
        ) {
            self.onMoveDelta  = onMoveDelta
            self.onScrollDelta = onScrollDelta
            self.onLeftClick  = onLeftClick
            self.onRightClick = onRightClick
            self.onSwipeLeft  = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            self.onSwipeUp    = onSwipeUp
            self.onSwipeDown  = onSwipeDown
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let location = recognizer.location(in: recognizer.view)
            let count = recognizer.numberOfTouches

            switch recognizer.state {
            case .began:
                lastLocation = location
                lastTouchCount = count

            case .changed:
                // If finger count changed mid-gesture, reset to avoid a jump
                if count != lastTouchCount {
                    lastLocation = location
                    lastTouchCount = count
                    return
                }
                guard let last = lastLocation else {
                    lastLocation = location
                    return
                }
                let dx = location.x - last.x
                let dy = location.y - last.y
                if count == 1 {
                    onMoveDelta(dx, dy)
                } else {
                    onScrollDelta(dx, dy)
                }
                lastLocation = location

            case .ended, .cancelled, .failed:
                lastLocation = nil
                lastTouchCount = 0

            default:
                break
            }
        }

        @objc func handleLeftTap()    { onLeftClick() }
        @objc func handleRightTap()   { onRightClick() }
        @objc func handleSwipeLeft()  { onSwipeLeft() }
        @objc func handleSwipeRight() { onSwipeRight() }
        @objc func handleSwipeUp()    { onSwipeUp() }
        @objc func handleSwipeDown()  { onSwipeDown() }
    }
}
