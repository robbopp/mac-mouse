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
import time
import ctypes
from ctypes import c_uint32, c_uint64, c_int, c_long, c_void_p, c_char_p, c_bool, byref

try:
    import Quartz
except ImportError:
    print("Missing dependency. Run:")
    print("  pip3 install pyobjc-framework-Quartz")
    sys.exit(1)

PORT = 5050
DISCOVERY_PORT = 5051          # UDP broadcast discovery fallback
SERVICE_NAME = "Robert's MacBook Pro"
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


# ── Space switching via CGSPrivate ───────────────────────────────────────────
# Uses the same private API as Hammerspoon / yabai — directly tells the window
# server to activate a specific space by ID, no keyboard shortcuts required.

_cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
_cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')

_cg.CGSMainConnectionID.restype          = c_uint32
_cg.CGSGetActiveSpace.argtypes           = [c_uint32]
_cg.CGSGetActiveSpace.restype            = c_uint64
_cg.CGSCopyManagedDisplaySpaces.argtypes = [c_uint32]
_cg.CGSCopyManagedDisplaySpaces.restype  = c_void_p
_cg.CGSManagedDisplaySetCurrentSpace.argtypes = [c_uint32, c_void_p, c_uint64]
_cg.CGSManagedDisplaySetCurrentSpace.restype  = c_int

_cf.CFRelease.argtypes              = [c_void_p]
_cf.CFArrayGetCount.argtypes        = [c_void_p]
_cf.CFArrayGetCount.restype         = c_long
_cf.CFArrayGetValueAtIndex.argtypes = [c_void_p, c_long]
_cf.CFArrayGetValueAtIndex.restype  = c_void_p
_cf.CFDictionaryGetValue.argtypes   = [c_void_p, c_void_p]
_cf.CFDictionaryGetValue.restype    = c_void_p
_cf.CFNumberGetValue.argtypes       = [c_void_p, c_int, c_void_p]
_cf.CFNumberGetValue.restype        = c_bool
_cf.CFStringCreateWithCString.argtypes = [c_void_p, c_char_p, c_uint32]
_cf.CFStringCreateWithCString.restype  = c_void_p

_kCFStringEncodingUTF8 = 0x08000100
_kCFNumberSInt64Type   = 4

def _cfstr(s):
    return _cf.CFStringCreateWithCString(None, s.encode('utf-8'), _kCFStringEncodingUTF8)

# Pre-create dictionary keys once for the process lifetime
_KEY_SPACES  = _cfstr('Spaces')
_KEY_ID64    = _cfstr('id64')
_KEY_DISP_ID = _cfstr('Display Identifier')


def _cf_num_i64(cf_num):
    val = c_uint64(0)
    _cf.CFNumberGetValue(cf_num, _kCFNumberSInt64Type, byref(val))
    return val.value


def _switch_space(direction):
    """Switch Spaces: direction = -1 (prev/left) or +1 (next/right)."""
    conn   = _cg.CGSMainConnectionID()
    active = _cg.CGSGetActiveSpace(conn)

    displays = _cg.CGSCopyManagedDisplaySpaces(conn)
    if not displays:
        return
    try:
        for i in range(_cf.CFArrayGetCount(displays)):
            display   = _cf.CFArrayGetValueAtIndex(displays, i)
            uuid_cf   = _cf.CFDictionaryGetValue(display, _KEY_DISP_ID)
            spaces_cf = _cf.CFDictionaryGetValue(display, _KEY_SPACES)
            if not uuid_cf or not spaces_cf:
                continue

            ids = []
            for j in range(_cf.CFArrayGetCount(spaces_cf)):
                sp    = _cf.CFArrayGetValueAtIndex(spaces_cf, j)
                id_cf = _cf.CFDictionaryGetValue(sp, _KEY_ID64)
                if id_cf:
                    ids.append(_cf_num_i64(id_cf))

            if active not in ids:
                continue

            new_idx = ids.index(active) + direction
            if 0 <= new_idx < len(ids):
                _cg.CGSManagedDisplaySetCurrentSpace(conn, uuid_cf, ids[new_idx])
            break
    finally:
        _cf.CFRelease(displays)


def swipe_left():  _switch_space(-1)   # switch to previous space
def swipe_right(): _switch_space(+1)   # switch to next space
_kVK_UpArrow   = 0x7E
_kVK_DownArrow = 0x7D

def _post_key(keycode, flags):
    src  = Quartz.CGEventSourceCreate(Quartz.kCGEventSourceStateHIDSystemState)
    down = Quartz.CGEventCreateKeyboardEvent(src, keycode, True)
    up   = Quartz.CGEventCreateKeyboardEvent(src, keycode, False)
    Quartz.CGEventSetFlags(down, flags)
    Quartz.CGEventSetFlags(up,   flags)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)

def swipe_up():   _post_key(_kVK_UpArrow,   Quartz.kCGEventFlagMaskControl)  # Mission Control
def swipe_down(): _post_key(_kVK_DownArrow, Quartz.kCGEventFlagMaskControl)  # App Exposé


# ── UDP broadcast discovery fallback ────────────────────────────────────────

def _broadcast_loop():
    """
    Broadcast server presence every 2 seconds on DISCOVERY_PORT.
    Works as a fallback when mDNS multicast is filtered by the router.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    msg = json.dumps({"type": "discover", "name": SERVICE_NAME, "port": PORT}).encode()
    while True:
        try:
            sock.sendto(msg, ('255.255.255.255', DISCOVERY_PORT))
        except Exception:
            pass
        time.sleep(2)


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
    threading.Thread(target=_broadcast_loop, daemon=True).start()
    print(f"Broadcasting on UDP port {DISCOVERY_PORT} (multicast fallback)")

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
            if   t == 'move':        move(pkt.get('dx', 0), pkt.get('dy', 0))
            elif t == 'click':       left_click()
            elif t == 'rightClick':  right_click()
            elif t == 'scroll':      scroll(pkt.get('dx', 0), pkt.get('dy', 0))
            elif t == 'swipeLeft':   swipe_left()
            elif t == 'swipeRight':  swipe_right()
            elif t == 'swipeUp':     swipe_up()
            elif t == 'swipeDown':   swipe_down()
        except (json.JSONDecodeError, KeyError):
            pass


if __name__ == '__main__':
    main()
