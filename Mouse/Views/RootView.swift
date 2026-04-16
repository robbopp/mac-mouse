// Mouse/Views/RootView.swift
import SwiftUI
import UIKit

/// Root router. Shows ServerPickerView when not connected, TrackpadView when connected.
struct RootView: View {
    @State private var connectionVM = ConnectionViewModel()

    var body: some View {
        switch connectionVM.connectionState {
        case .connected:
            TrackpadView(
                networkService: connectionVM.networkService,
                onDisconnect: { connectionVM.disconnect() }
            )
            .ignoresSafeArea()
        default:
            ServerPickerView(connectionVM: connectionVM)
        }
    }
}

private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
    appLockLandscape = (mask == .landscape)
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
}
