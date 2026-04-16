# Mouse App — Architecture Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Mouse from a single-file implementation into a clean MVVM + Service Layer architecture with full trackpad gestures (move, left-click, right-click, scroll), Bonjour server auto-discovery with manual IP fallback, and a polished UI.

**Architecture:** MVVM + Service Layer. Views observe ViewModels; ViewModels coordinate with Services; Services have no SwiftUI dependencies. The project uses `PBXFileSystemSynchronizedRootGroup`, so all new Swift files dropped into `Mouse/` subdirectories are auto-discovered by Xcode — no `.pbxproj` edits needed for source files.

**Tech Stack:** SwiftUI, Network framework (`NWConnection`, `NWBrowser`), UIKit (`UIViewRepresentable` for multi-touch gestures), `UserDefaults`, `@Observable` (iOS 17+), iOS 18.5+

---

## File Map

**Create:**
- `Mouse/Models/MouseEvent.swift` — `Encodable` enum for wire protocol
- `Mouse/Models/ServerConfig.swift` — server identity (Bonjour name or host/port)
- `Mouse/Models/ConnectionState.swift` — connection state enum
- `Mouse/Services/NetworkService.swift` — owns UDP `NWConnection`, sends events
- `Mouse/Services/DiscoveryService.swift` — `NWBrowser` Bonjour scanning
- `Mouse/ViewModels/TrackpadViewModel.swift` — gesture accumulation, 60fps flush timer
- `Mouse/ViewModels/ConnectionViewModel.swift` — connection lifecycle, `UserDefaults`
- `Mouse/Views/ToolbarView.swift` — bottom toolbar (right-click button, disconnect)
- `Mouse/Views/ServerPickerView.swift` — discovered server list + manual IP form
- `Mouse/Views/TrackpadView.swift` — full-screen UIViewRepresentable gesture surface
- `Mouse/Views/RootView.swift` — root router (picker ↔ trackpad)
- `Mouse/Info.plist` — local network permission + Bonjour service type declaration

**Modify:**
- `Mouse/MouseApp.swift` — swap `ContentView` → `RootView`
- `Mouse.xcodeproj/project.pbxproj` — disable auto-generated Info.plist, point to `Mouse/Info.plist`

**Delete:**
- `Mouse/ContentView.swift`

---

## Mac server note

The app sends UDP JSON to a server running on the Mac. That server must:
1. Listen on UDP port `5050`
2. Handle packets: `{"type":"move","dx":N,"dy":N}`, `{"type":"click"}`, `{"type":"rightClick"}`, `{"type":"scroll","dx":N,"dy":N}`
3. Advertise itself via Bonjour as `_mouse._udp.` for auto-discovery to work

---

## Task 1: Models

**Files:**
- Create: `Mouse/Models/MouseEvent.swift`
- Create: `Mouse/Models/ServerConfig.swift`
- Create: `Mouse/Models/ConnectionState.swift`

- [ ] **Step 1: Create `Mouse/Models/` directory and `MouseEvent.swift`**

```swift
// Mouse/Models/MouseEvent.swift
import Foundation

enum MouseEvent: Encodable {
    case move(dx: Double, dy: Double)
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
```

- [ ] **Step 2: Create `ServerConfig.swift`**

```swift
// Mouse/Models/ServerConfig.swift
import Foundation

struct ServerConfig: Identifiable, Hashable, Codable {
    let id: UUID
    let displayName: String
    /// Set for Bonjour-discovered servers. Used to build NWEndpoint.service.
    let bonjourName: String?
    /// Set for manually-entered servers.
    let host: String?
    let port: UInt16

    static func bonjour(name: String) -> ServerConfig {
        ServerConfig(id: UUID(), displayName: name, bonjourName: name, host: nil, port: 5050)
    }

    static func manual(host: String, port: UInt16) -> ServerConfig {
        ServerConfig(id: UUID(), displayName: "\(host):\(port)", bonjourName: nil, host: host, port: port)
    }
}
```

- [ ] **Step 3: Create `ConnectionState.swift`**

```swift
// Mouse/Models/ConnectionState.swift

enum ConnectionState {
    case discovering
    case connecting
    case connected
    case disconnected
    case error(String)
}
```

- [ ] **Step 4: Verify in Xcode**

Open the project in Xcode. The `Models/` group should appear automatically in the file navigator (Xcode auto-discovers it via `PBXFileSystemSynchronizedRootGroup`). Confirm all three files appear and the project builds with ⌘B (no errors expected — these are pure value types with no dependencies).

- [ ] **Step 5: Commit**

```bash
git add Mouse/Models/
git commit -m "feat: add Mouse, ServerConfig, ConnectionState models"
```

---

## Task 2: NetworkService

**Files:**
- Create: `Mouse/Services/NetworkService.swift`

- [ ] **Step 1: Create `Mouse/Services/` directory and `NetworkService.swift`**

```swift
// Mouse/Services/NetworkService.swift
import Network
import Foundation

/// Owns a single UDP NWConnection. Sends MouseEvents as JSON.
/// Call connect(to:) to establish or re-establish the connection.
/// Set onStateChange to be notified of state transitions.
final class NetworkService {
    /// Called on the main queue whenever the underlying NWConnection state changes.
    var onStateChange: ((NWConnection.State) -> Void)?

    private var connection: NWConnection?

    func connect(to config: ServerConfig) {
        connection?.cancel()

        let endpoint: NWEndpoint
        if let bonjourName = config.bonjourName {
            endpoint = .service(
                name: bonjourName,
                type: "_mouse._udp.",
                domain: "local.",
                interface: nil
            )
        } else if let host = config.host, let port = NWEndpoint.Port(rawValue: config.port) {
            endpoint = .hostPort(host: NWEndpoint.Host(host), port: port)
        } else {
            return
        }

        let params = NWParameters.udp
        connection = NWConnection(to: endpoint, using: params)
        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.onStateChange?(state)
            }
        }
        connection?.start(queue: .main)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    func send(_ event: MouseEvent) {
        guard let connection, let data = try? JSONEncoder().encode(event) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
```

- [ ] **Step 2: Verify build in Xcode**

Build with ⌘B. Expected: no errors. `NetworkService.swift` should appear under `Services/` in the navigator.

- [ ] **Step 3: Commit**

```bash
git add Mouse/Services/NetworkService.swift
git commit -m "feat: add NetworkService (UDP NWConnection)"
```

---

## Task 3: DiscoveryService

**Files:**
- Create: `Mouse/Services/DiscoveryService.swift`

- [ ] **Step 1: Create `DiscoveryService.swift`**

```swift
// Mouse/Services/DiscoveryService.swift
import Network
import Foundation

/// Browses for _mouse._udp. Bonjour services on the local network.
/// Results are delivered to onServersChanged on the main queue.
final class DiscoveryService {
    var onServersChanged: (([ServerConfig]) -> Void)?
    private var browser: NWBrowser?

    func start() {
        let params = NWParameters()
        params.includePeerToPeer = false

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_mouse._udp.", domain: "local."),
            using: params
        )

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            let servers: [ServerConfig] = results.compactMap { result in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return .bonjour(name: name)
            }
            DispatchQueue.main.async {
                self?.onServersChanged?(servers)
            }
        }

        browser?.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
```

- [ ] **Step 2: Verify build in Xcode**

Build with ⌘B. Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Mouse/Services/DiscoveryService.swift
git commit -m "feat: add DiscoveryService (NWBrowser Bonjour)"
```

---

## Task 4: TrackpadViewModel

**Files:**
- Create: `Mouse/ViewModels/TrackpadViewModel.swift`

- [ ] **Step 1: Create `Mouse/ViewModels/` directory and `TrackpadViewModel.swift`**

```swift
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
```

- [ ] **Step 2: Verify build in Xcode**

Build with ⌘B. Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Mouse/ViewModels/TrackpadViewModel.swift
git commit -m "feat: add TrackpadViewModel (gesture accumulation + 60fps flush)"
```

---

## Task 5: ConnectionViewModel

**Files:**
- Create: `Mouse/ViewModels/ConnectionViewModel.swift`

- [ ] **Step 1: Create `ConnectionViewModel.swift`**

```swift
// Mouse/ViewModels/ConnectionViewModel.swift
import Foundation

private let lastServerDefaultsKey = "lastConnectedServer"

/// Manages the full connection lifecycle:
/// - Starts Bonjour discovery on launch (or auto-reconnects to last server)
/// - Exposes discoveredServers for ServerPickerView
/// - Owns NetworkService (passed down to TrackpadViewModel when connected)
@Observable
final class ConnectionViewModel {
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var discoveredServers: [ServerConfig] = []
    private(set) var connectionError: String?

    let networkService = NetworkService()
    private let discoveryService = DiscoveryService()

    init() {
        discoveryService.onServersChanged = { [weak self] servers in
            self?.discoveredServers = servers
        }
        attemptAutoReconnect()
    }

    // MARK: - Public

    func connect(to config: ServerConfig) {
        discoveryService.stop()
        discoveredServers = []
        connectionState = .connecting
        connectionError = nil

        networkService.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                connectionState = .connected
                saveLastServer(config)
            case .failed(let error):
                connectionState = .error(error.localizedDescription)
                connectionError = error.localizedDescription
                startDiscovery()
            case .cancelled:
                // Only restart discovery if we weren't the ones cancelling intentionally
                if case .connecting = connectionState {
                    startDiscovery()
                }
            default:
                break
            }
        }

        networkService.connect(to: config)
    }

    func disconnect() {
        networkService.onStateChange = nil
        networkService.disconnect()
        connectionState = .disconnected
        startDiscovery()
    }

    // MARK: - Private

    private func attemptAutoReconnect() {
        guard
            let data = UserDefaults.standard.data(forKey: lastServerDefaultsKey),
            let config = try? JSONDecoder().decode(ServerConfig.self, from: data)
        else {
            startDiscovery()
            return
        }
        connect(to: config)
    }

    private func startDiscovery() {
        connectionState = .discovering
        discoveryService.start()
    }

    private func saveLastServer(_ config: ServerConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: lastServerDefaultsKey)
    }
}
```

- [ ] **Step 2: Verify build in Xcode**

Build with ⌘B. Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Mouse/ViewModels/ConnectionViewModel.swift
git commit -m "feat: add ConnectionViewModel (lifecycle + UserDefaults auto-reconnect)"
```

---

## Task 6: ToolbarView

**Files:**
- Create: `Mouse/Views/ToolbarView.swift`

- [ ] **Step 1: Create `Mouse/Views/` directory and `ToolbarView.swift`**

```swift
// Mouse/Views/ToolbarView.swift
import SwiftUI

struct ToolbarView: View {
    let onRightClick: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Button(action: onRightClick) {
                Label("Right Click", systemImage: "cursorarrow.click.2")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            Button(action: onDisconnect) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.black.opacity(0.4))
    }
}
```

- [ ] **Step 2: Verify in Xcode Preview**

Add a preview at the bottom of `ToolbarView.swift`:

```swift
#Preview {
    ToolbarView(onRightClick: {}, onDisconnect: {})
        .background(.gray)
}
```

Run the preview (⌘+Option+P). Confirm the toolbar renders: a "Right Click" button on the left, an X button on the right.

- [ ] **Step 3: Remove preview before committing**

Delete the `#Preview` block.

- [ ] **Step 4: Commit**

```bash
git add Mouse/Views/ToolbarView.swift
git commit -m "feat: add ToolbarView"
```

---

## Task 7: ServerPickerView

**Files:**
- Create: `Mouse/Views/ServerPickerView.swift`

- [ ] **Step 1: Create `ServerPickerView.swift`**

```swift
// Mouse/Views/ServerPickerView.swift
import SwiftUI

struct ServerPickerView: View {
    @Bindable var connectionVM: ConnectionViewModel
    @State private var manualHost = ""
    @State private var manualPort = "5050"

    var body: some View {
        NavigationStack {
            List {
                // Discovered servers section
                Section {
                    if connectionVM.discoveredServers.isEmpty {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Searching for Mouse servers…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(connectionVM.discoveredServers) { server in
                            Button {
                                connectionVM.connect(to: server)
                            } label: {
                                HStack {
                                    Image(systemName: "desktopcomputer")
                                    Text(server.displayName)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text("On this network")
                }

                // Manual entry section
                Section {
                    TextField("IP Address", text: $manualHost)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                    TextField("Port", text: $manualPort)
                        .keyboardType(.numberPad)
                    Button("Connect") {
                        guard
                            !manualHost.isEmpty,
                            let port = UInt16(manualPort)
                        else { return }
                        connectionVM.connect(to: .manual(host: manualHost, port: port))
                    }
                    .disabled(manualHost.isEmpty)
                } header: {
                    Text("Connect manually")
                }

                // Error banner
                if case .error(let msg) = connectionVM.connectionState {
                    Section {
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Mouse")
        }
    }
}
```

- [ ] **Step 2: Verify build in Xcode**

Build with ⌘B. Expected: no errors. (`@Bindable` requires `ConnectionViewModel` to be `@Observable`, which it is.)

- [ ] **Step 3: Commit**

```bash
git add Mouse/Views/ServerPickerView.swift
git commit -m "feat: add ServerPickerView (Bonjour list + manual IP entry)"
```

---

## Task 8: TrackpadView

**Files:**
- Create: `Mouse/Views/TrackpadView.swift`

Multi-touch gestures (1-finger drag, 2-finger drag, 1-finger tap, 2-finger tap) require UIKit gesture recognizers — SwiftUI's `DragGesture` is single-touch only. The view uses `UIViewRepresentable` to host a plain `UIView` with four recognizers attached.

- [ ] **Step 1: Create `TrackpadView.swift`**

```swift
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
```

- [ ] **Step 2: Verify build in Xcode**

Build with ⌘B. Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Mouse/Views/TrackpadView.swift
git commit -m "feat: add TrackpadView (UIViewRepresentable multi-touch gestures)"
```

---

## Task 9: RootView + wire entry point

**Files:**
- Create: `Mouse/Views/RootView.swift`
- Modify: `Mouse/MouseApp.swift`
- Delete: `Mouse/ContentView.swift`

- [ ] **Step 1: Create `RootView.swift`**

```swift
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
```

- [ ] **Step 2: Update `MouseApp.swift`**

Replace the contents of `Mouse/MouseApp.swift` with:

```swift
// Mouse/MouseApp.swift
import SwiftUI

@main
struct MouseApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 3: Delete `ContentView.swift`**

Delete `Mouse/ContentView.swift` from disk and from the Xcode project navigator (right-click → Delete → Move to Trash).

- [ ] **Step 4: Verify build in Xcode**

Build with ⌘B. Expected: no errors, no references to `ContentView` anywhere.

- [ ] **Step 5: Commit**

```bash
git add Mouse/Views/RootView.swift Mouse/MouseApp.swift
git rm Mouse/ContentView.swift
git commit -m "feat: add RootView, wire app entry point, remove ContentView"
```

---

## Task 10: Info.plist + project.pbxproj

iOS 14+ requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist for LAN access and Bonjour browsing. Because `NSBonjourServices` is an array, it can't be set via `INFOPLIST_KEY_*` build settings — a full Info.plist is needed.

**Files:**
- Create: `Mouse/Info.plist`
- Modify: `Mouse.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create `Mouse/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Mouse needs local network access to find and connect to your Mac.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_mouse._udp.</string>
    </array>
    <key>UIApplicationSceneManifest</key>
    <dict>
        <key>UIApplicationSupportsMultipleScenes</key>
        <false/>
        <key>UISceneConfigurations</key>
        <dict/>
    </dict>
    <key>UIApplicationSupportsIndirectInputEvents</key>
    <true/>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>armv7</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~iPad</key>
    <array>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Update `project.pbxproj` — target Debug build settings (`EB7203E92E12F01E00CE603D`)**

In the `EB7203E92E12F01E00CE603D /* Debug */` build configuration block, make these changes:

Replace:
```
GENERATE_INFOPLIST_FILE = YES;
```
With:
```
GENERATE_INFOPLIST_FILE = NO;
INFOPLIST_FILE = Mouse/Info.plist;
```

Also remove these lines (they are superseded by Info.plist):
```
INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
INFOPLIST_KEY_UILaunchScreen_Generation = YES;
INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown";
```

- [ ] **Step 3: Update `project.pbxproj` — target Release build settings (`EB7203EA2E12F01E00CE603D`)**

Apply the identical changes to the `EB7203EA2E12F01E00CE603D /* Release */` block.

- [ ] **Step 4: Verify build in Xcode**

Build with ⌘B. Expected: no errors.

To confirm the Info.plist is being used correctly: in Xcode, select the Mouse target → Info tab. You should see `NSLocalNetworkUsageDescription` and `NSBonjourServices` in the list.

- [ ] **Step 5: Commit**

```bash
git add Mouse/Info.plist Mouse.xcodeproj/project.pbxproj
git commit -m "feat: add Info.plist with local network + Bonjour permissions"
```

---

## Final verification

- [ ] Build the app on a real iPhone (⌘R with device selected as destination)
- [ ] On first launch: iOS prompts "Mouse would like to find devices on your local network" — tap Allow
- [ ] With Mac server running and advertising `_mouse._udp.`: server appears in the list automatically
- [ ] Tap a server → app switches to the black trackpad surface
- [ ] 1-finger drag moves the Mac cursor
- [ ] 1-finger tap clicks
- [ ] 2-finger drag scrolls
- [ ] 2-finger tap right-clicks
- [ ] "Right Click" button in toolbar sends a right-click
- [ ] X button disconnects and returns to the server picker
- [ ] Force-quit and relaunch: app auto-reconnects to the last server
