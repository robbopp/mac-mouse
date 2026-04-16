# Mouse App — Architecture Design
**Date:** 2026-04-16
**Status:** Approved

## Overview

Mouse is an iOS app (iPhone + iPad, iOS 18.5+) that turns the device into a wireless trackpad for a Mac. It communicates over UDP (JSON payloads) on the local network.

This document describes the target architecture: MVVM + Service Layer, replacing the current single-file implementation.

---

## Goals

- Fix existing bugs: tap fires on drag-end, hardcoded server IP, timer never cleaned up, missing Local Network permission entry
- Add full trackpad gestures: left click, right click, scroll, move
- Add server discovery: Bonjour/mDNS auto-discovery with manual IP fallback
- Clean separation of concerns: each unit has one job and communicates through defined interfaces

---

## Layer Overview

```
Views
  └── ViewModels
        └── Services
              └── Models
```

Each layer only depends on the layer below it. Views never access Services directly.

---

## Models

Plain Swift value types with no logic.

**`MouseEvent`** (`Models/MouseEvent.swift`)
```swift
enum MouseEvent {
    case move(dx: Double, dy: Double)
    case leftClick
    case rightClick
    case scroll(dx: Double, dy: Double)
}
```

**`ServerConfig`** (`Models/ServerConfig.swift`)
```swift
struct ServerConfig: Codable, Hashable {
    let host: String
    let port: UInt16
    let name: String?   // Bonjour display name, nil for manual entries
}
```

**`ConnectionState`** (`Models/ConnectionState.swift`)
```swift
enum ConnectionState {
    case discovering
    case connecting
    case connected(ServerConfig)
    case disconnected
    case error(String)
}
```

---

## Services

Plain Swift classes with no SwiftUI dependencies. No knowledge of each other.

### `NetworkService` (`Services/NetworkService.swift`)

**Responsibility:** Own the UDP connection and send mouse events.

- Takes a `ServerConfig` to connect to
- Exposes `connect(to: ServerConfig)`, `disconnect()`, `send(_ event: MouseEvent)`
- Serializes `MouseEvent` to JSON internally
- Handles reconnection with exponential backoff on connection loss
- Reports state changes via a closure/publisher: `onStateChange: (ConnectionState) -> Void`

**JSON wire format:**
```json
{ "type": "move",  "dx": 12.5, "dy": -3.0 }
{ "type": "click" }
{ "type": "rightClick" }
{ "type": "scroll", "dx": 0.0, "dy": -5.0 }
```

### `DiscoveryService` (`Services/DiscoveryService.swift`)

**Responsibility:** Find Mouse servers on the local network via Bonjour.

- Uses `NWBrowser` to browse for `_mouse._udp.local.`
- Publishes `[ServerConfig]` as servers appear/disappear
- `start()` / `stop()` — called by `ConnectionViewModel` (stopped once connected)

---

## ViewModels

Both are `@Observable` classes.

### `ConnectionViewModel` (`ViewModels/ConnectionViewModel.swift`)

**Responsibility:** Manage the connection lifecycle.

- Owns `DiscoveryService` and `NetworkService`
- Exposes:
  - `connectionState: ConnectionState`
  - `discoveredServers: [ServerConfig]`
- Actions:
  - `connect(to: ServerConfig)` — stops discovery, tells NetworkService to connect
  - `connectManual(host: String, port: UInt16)` — same but from user-typed values
  - `disconnect()` — disconnects, restarts discovery
- On app launch: checks `UserDefaults` for last successful `ServerConfig`, auto-reconnects if found
- On successful connection: saves `ServerConfig` to `UserDefaults`

### `TrackpadViewModel` (`ViewModels/TrackpadViewModel.swift`)

**Responsibility:** Translate gestures into mouse events and flush them at 60fps.

- Receives `NetworkService` injected from `ConnectionViewModel`
- Owns the 60fps flush `Timer` — started on init, invalidated in `deinit`
- Accumulates move/scroll deltas between timer ticks
- Exposes gesture handlers:
  - `onDragChanged(dx: Double, dy: Double)`
  - `onDragEnded(totalDistance: Double)`
  - `onTwoFingerScrollChanged(dx: Double, dy: Double)`
  - `onTwoFingerTap()`
  - `onToolbarRightClick()`
- **Tap fix:** tracks accumulated drag distance per gesture. In `onDragEnded`, if `totalDistance < 5pt`, fires `.leftClick` instead of nothing. No simultaneous gesture composition needed.
- Applies 4x scaling factor to move deltas before sending

---

## Views

### `RootView` (`Views/RootView.swift`)

- Observes `ConnectionViewModel`
- Shows `ServerPickerView` when state is `.discovering`, `.disconnected`, or `.error`
- Shows `TrackpadView` when state is `.connected`
- Only view that owns `ConnectionViewModel`

### `ServerPickerView` (`Views/ServerPickerView.swift`)

- Lists `ConnectionViewModel.discoveredServers` — tap any row to connect
- Spinner while state is `.discovering`
- "Connect manually" section: IP + port text fields + Connect button
- Error banner when state is `.error`

### `TrackpadView` (`Views/TrackpadView.swift`)

- Full-screen `Color.clear` gesture surface (`.edgesIgnoringSafeArea(.all)`)
- Owns `TrackpadViewModel` (initialized with the connected `NetworkService`)
- Wires gestures:
  - 1-finger `DragGesture` → `onDragChanged` / `onDragEnded`
  - 2-finger drag → `onTwoFingerScrollChanged` (requires `UIViewRepresentable` wrapping `UIPanGestureRecognizer` with `minimumNumberOfTouches = 2`, since SwiftUI has no native 2-finger drag)
  - 2-finger `TapGesture(count: 1)` with `.simultaneously` with a 2-touch recognizer → `onTwoFingerTap`
- Embeds `ToolbarView` pinned to the bottom

### `ToolbarView` (`Views/ToolbarView.swift`)

- Right-click button → `TrackpadViewModel.onToolbarRightClick()`
- Disconnect/settings button → calls `ConnectionViewModel.disconnect()`

---

## File Structure

```
Mouse/
  Models/
    MouseEvent.swift
    ServerConfig.swift
    ConnectionState.swift
  Services/
    NetworkService.swift
    DiscoveryService.swift
  ViewModels/
    ConnectionViewModel.swift
    TrackpadViewModel.swift
  Views/
    RootView.swift
    ServerPickerView.swift
    TrackpadView.swift
    ToolbarView.swift
  MouseApp.swift
  Assets.xcassets/
docs/
  superpowers/
    specs/
      2026-04-16-mouse-architecture-design.md
```

---

## Bug Fixes Included

| Bug | Fix |
|-----|-----|
| Tap fires on drag-end | Distance threshold in `TrackpadViewModel.onDragEnded` |
| Hardcoded server IP | `ServerPickerView` + `ConnectionViewModel` |
| Timer never invalidated | `Timer` invalidated in `TrackpadViewModel.deinit` |
| Missing Local Network permission | Add `NSLocalNetworkUsageDescription` + `NSBonjourServices` to Info.plist |

---

## Out of Scope

- Keyboard panel
- Media controls
- App switcher
- Multi-device support
