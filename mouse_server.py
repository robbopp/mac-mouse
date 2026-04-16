#!/usr/bin/env python3
"""
Mouse Mac Server
Receives UDP packets from the Mouse iOS app and controls the Mac cursor.

Setup (one time):
    pip3 install pyobjc-framework-Quartz

Then grant Accessibility permission to Terminal:
    System Settings → Privacy & Security → Accessibility → add Terminal (or iTerm2)

Usage:
    python3 mouse_server.py
"""

import socket
import json
import subprocess
import sys
import signal
import threading

try:
    import Quartz
except ImportError:
    print("Missing dependency. Run:")
    print("  pip3 install pyobjc-framework-Quartz")
    sys.exit(1)

PORT = 5050
SERVICE_NAME = "Mouse Server"
SERVICE_TYPE = "_mouse._udp"   # no trailing dot — dns-sd adds it


# ── Mouse control ────────────────────────────────────────────────────────────

def get_position():
    loc = Quartz.CGEventGetLocation(Quartz.CGEventCreate(None))
    return loc.x, loc.y


def move(dx, dy):
    x, y = get_position()
    bounds = Quartz.CGDisplayBounds(Quartz.CGMainDisplayID())
    x = max(0, min(x + dx, bounds.size.width  - 1))
    y = max(0, min(y + dy, bounds.size.height - 1))
    e = Quartz.CGEventCreateMouseEvent(
        None, Quartz.kCGEventMouseMoved,
        Quartz.CGPoint(x, y), Quartz.kCGMouseButtonLeft
    )
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)


def left_click():
    x, y = get_position()
    pos = Quartz.CGPoint(x, y)
    for t in (Quartz.kCGEventLeftMouseDown, Quartz.kCGEventLeftMouseUp):
        e = Quartz.CGEventCreateMouseEvent(None, t, pos, Quartz.kCGMouseButtonLeft)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)


def right_click():
    x, y = get_position()
    pos = Quartz.CGPoint(x, y)
    for t in (Quartz.kCGEventRightMouseDown, Quartz.kCGEventRightMouseUp):
        e = Quartz.CGEventCreateMouseEvent(None, t, pos, Quartz.kCGMouseButtonRight)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)


def scroll(dx, dy):
    # Positive wheel1 = scroll up. Negate dy so finger-down scrolls content down.
    e = Quartz.CGEventCreateScrollWheelEvent(
        None, Quartz.kCGScrollEventUnitPixel,
        2, int(-dy), int(-dx)
    )
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)


# ── Bonjour advertisement ────────────────────────────────────────────────────

def _run_bonjour(proc_box):
    cmd = ['dns-sd', '-R', SERVICE_NAME, SERVICE_TYPE, 'local', str(PORT)]
    print(f"Bonjour: {' '.join(cmd)}")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    proc_box[0] = proc
    for line in proc.stdout:
        print(f"[dns-sd] {line.rstrip()}")


def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return '?.?.?.?'


# ── Main loop ────────────────────────────────────────────────────────────────

def main():
    ip = get_local_ip()
    print(f"Mouse Server — UDP port {PORT}")
    print(f"Mac IP (for manual entry): {ip}")
    print(f"Advertising '{SERVICE_NAME}' via Bonjour")
    print("Ctrl+C to stop\n")

    proc_box = [None]
    threading.Thread(target=_run_bonjour, args=(proc_box,), daemon=True).start()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('', PORT))
    sock.settimeout(1.0)

    def shutdown(sig, frame):
        print("\nStopped.")
        if proc_box[0]:
            proc_box[0].terminate()
        sock.close()
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    print("Waiting for iPhone…\n")

    connected_addr = None
    while True:
        try:
            data, addr = sock.recvfrom(4096)
        except socket.timeout:
            continue
        except OSError:
            break

        if addr != connected_addr:
            print(f"Connected: {addr[0]}")
            connected_addr = addr

        try:
            pkt = json.loads(data.decode('utf-8'))
            t = pkt.get('type')
            if   t == 'move':       move(pkt.get('dx', 0), pkt.get('dy', 0))
            elif t == 'click':      left_click()
            elif t == 'rightClick': right_click()
            elif t == 'scroll':     scroll(pkt.get('dx', 0), pkt.get('dy', 0))
        except (json.JSONDecodeError, KeyError):
            pass


if __name__ == '__main__':
    main()
