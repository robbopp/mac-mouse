// Mouse/Views/RootView.swift
import SwiftUI

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
