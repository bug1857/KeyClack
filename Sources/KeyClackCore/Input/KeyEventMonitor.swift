import Foundation
import CoreGraphics
import AppKit

/// Global, read-only keyboard event monitor built on macOS CGEventTap (.listenOnly).
/// Captures keyDown, keyUp, and left/right modifier flagsChanged with sub-millisecond overhead
/// and cannot block or freeze system keyboard input.
final class KeyEventMonitor {
    var onKeyEvent: ((UInt16, Bool) -> Void)?
    var onPermissionChanged: ((Bool) -> Void)?
    var ignoreKeyRepeat: Bool = true

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionRetryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    private var heldModifiers: Set<UInt16> = []

    /// Returns true if macOS Input Monitoring permission has been granted.
    static var hasPermission: Bool {
        CGPreflightListenEventAccess()
    }

    /// Prompts macOS to display the Input Monitoring permission dialog if not yet authorized.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    /// Opens macOS System Settings directly to Privacy & Security -> Input Monitoring.
    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Starts listening for global key events. If permission is missing, polls lightly until granted.
    func start() {
        stop()
        observeSystemWake()
        if installTap() {
            onPermissionChanged?(true)
        } else {
            onPermissionChanged?(false)
            startPermissionWatcher()
        }
    }

    func stop() {
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        heldModifiers.removeAll()
    }

    deinit {
        stop()
    }

    private func observeSystemWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.heldModifiers.removeAll()
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else if Self.hasPermission, self.installTap() {
                self.onPermissionChanged?(true)
            }
        }
    }

    private func startPermissionWatcher() {
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Self.hasPermission && self.installTap() {
                self.permissionRetryTimer?.invalidate()
                self.permissionRetryTimer = nil
                self.onPermissionChanged?(true)
            }
        }
    }

    private func installTap() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if ignoreKeyRepeat && isAutoRepeat {
                return
            }
            onKeyEvent?(keyCode, true)

        case .keyUp:
            onKeyEvent?(keyCode, false)

        case .flagsChanged:
            handleModifierChange(keyCode: keyCode, flags: event.flags)

        default:
            break
        }
    }

    /// Distinguishes individual left/right Shift, Command, Option, Control, Caps Lock, and Fn
    /// presses & releases using macOS IOKit device-dependent modifier masks.
    private func handleModifierChange(keyCode: UInt16, flags: CGEventFlags) {
        let raw = flags.rawValue
        let isCurrentlyDown: Bool

        switch keyCode {
        case 56: // Left Shift (NX_DEVICELSHIFTKEYMASK)
            isCurrentlyDown = (raw & 0x0000_0002) != 0
        case 60: // Right Shift (NX_DEVICERSHIFTKEYMASK)
            isCurrentlyDown = (raw & 0x0000_0004) != 0
        case 55: // Left Command (NX_DEVICELCMDKEYMASK)
            isCurrentlyDown = (raw & 0x0000_0008) != 0
        case 54: // Right Command (NX_DEVICERCMDKEYMASK)
            isCurrentlyDown = (raw & 0x0000_0010) != 0
        case 58: // Left Option (NX_DEVICELALTKEYMASK)
            isCurrentlyDown = (raw & 0x0000_0020) != 0
        case 61: // Right Option (NX_DEVICERALTKEYMASK)
            isCurrentlyDown = (raw & 0x0000_0040) != 0
        case 59: // Left Control (NX_DEVICELCTLKEYMASK)
            isCurrentlyDown = (raw & 0x0000_0001) != 0
        case 62: // Right Control (NX_DEVICERCTLKEYMASK)
            isCurrentlyDown = (raw & 0x0000_2000) != 0
        case 57: // Caps Lock (toggle state; emit crisp press click on change)
            onKeyEvent?(keyCode, true)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(45)) { [weak self] in
                self?.onKeyEvent?(keyCode, false)
            }
            return
        case 63: // Fn / Globe key
            isCurrentlyDown = flags.contains(.maskSecondaryFn)
        default:
            return
        }

        let wasDown = heldModifiers.contains(keyCode)
        if isCurrentlyDown && !wasDown {
            heldModifiers.insert(keyCode)
            onKeyEvent?(keyCode, true)
        } else if !isCurrentlyDown && wasDown {
            heldModifiers.remove(keyCode)
            onKeyEvent?(keyCode, false)
        }
    }
}
