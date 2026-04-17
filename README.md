# 🖱️ mac-mouse

> Turn your iPhone into a wireless mouse for your MacBook.

mac-mouse is a two-part project — a Swift iOS app that tracks touch input on your iPhone, and a lightweight Python server running on your Mac that translates that input into real mouse movement.

---

## How It Works

1. **iPhone (Swift app)** — Captures touch gestures and streams them over your local network.
2. **Mac (Python server)** — Receives the gesture data and controls the system cursor accordingly.

---

## Requirements

- iPhone running iOS 16+
- MacBook on the same Wi-Fi network
- Python 3.x
- Xcode (to build and install the iOS app)

---

## Setup

### 1. Run the Mac server

```bash
python3 mouse_server.py
```

Note the IP address printed in the terminal — you'll need it in the next step.

### 2. Build & run the iOS app

- Open `Mouse.xcodeproj` in Xcode
- Connect your iPhone and select it as the build target
- Build and run (`Cmd + R`)
- Enter your Mac's IP address in the app when prompted

### 3. Use your iPhone as a mouse

- **Swipe** to move the cursor
- **Tap** to left-click

---

## Project Structure

```
mac-mouse/
├── Mouse.xcodeproj/     # Xcode project
├── Mouse/               # Swift iOS app source
├── mouse_server.py      # Python server for macOS
└── docs/
    └── superpowers/     # Additional documentation
```

---

## Languages

- Swift (74%) — iOS client
- Python (26%) — Mac server

---

## Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you'd like to change.
