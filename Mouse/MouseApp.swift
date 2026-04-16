// Mouse/MouseApp.swift
import SwiftUI
import UIKit

// Shared flag: TrackpadView sets this to true so the app locks to landscape.
// AppDelegate reads it to enforce the restriction.
var appLockLandscape = false

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        appLockLandscape ? .landscape : [.portrait, .landscapeLeft, .landscapeRight]
    }
}

@main
struct MouseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
