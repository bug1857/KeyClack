import Foundation

/// Acoustic size/stabilizer class of a physical MacBook key.
enum KeyCategory: Int, CaseIterable, Hashable {
    case alpha = 0
    case space = 1
    case enter = 2
    case backspace = 3
    case shift = 4
    case modifier = 5

    /// Pitch multiplier relative to a standard 1u alpha keycap.
    var pitchMultiplier: Float {
        switch self {
        case .alpha: return 1.0
        case .space: return 0.64
        case .enter: return 0.79
        case .backspace: return 0.81
        case .shift: return 0.86
        case .modifier: return 0.90
        }
    }

    /// Decay multiplier (larger hollow keycaps resonate slightly longer).
    var decayMultiplier: Float {
        switch self {
        case .alpha: return 1.0
        case .space: return 1.28
        case .enter: return 1.14
        case .backspace: return 1.12
        case .shift: return 1.08
        case .modifier: return 1.04
        }
    }

    /// Relative gain multiplier.
    var gainMultiplier: Float {
        switch self {
        case .alpha: return 1.0
        case .space: return 1.16
        case .enter: return 1.08
        case .backspace: return 1.06
        case .shift: return 0.94
        case .modifier: return 0.88
        }
    }

    /// Stabilizer micro-offset in milliseconds (simulates 2u–6.25u wire stems landing slightly asynchronously).
    var stabilizerOffsetMs: Float {
        switch self {
        case .space: return 1.85
        case .enter: return 1.15
        case .backspace: return 1.05
        case .shift: return 0.85
        case .alpha, .modifier: return 0.0
        }
    }
}

/// Complete physical metadata for a macOS CGKeyCode.
struct KeyInfo {
    let keyCode: UInt16
    let label: String
    let pan: Float            // -1.0 (far left) ... +1.0 (far right)
    let category: KeyCategory
    let v1Code: Int?          // Classic Mechvibes V1 uiohook scan code
    let w3cCode: String       // MechvibesDX V2 / W3C KeyboardEvent.code
}

/// Maps macOS virtual key codes (CGKeyCode) to physical MacBook horizontal positions,
/// stabilizer categories, and Mechvibes V1 / V2 key identifiers.
enum KeyLayoutMap {
    static let allKeys: [KeyInfo] = [
        // Top / Number Row
        KeyInfo(keyCode: 53, label: "esc", pan: -0.95, category: .modifier, v1Code: 1, w3cCode: "Escape"),
        KeyInfo(keyCode: 50, label: "`", pan: -0.92, category: .alpha, v1Code: 41, w3cCode: "Backquote"),
        KeyInfo(keyCode: 18, label: "1", pan: -0.80, category: .alpha, v1Code: 2, w3cCode: "Digit1"),
        KeyInfo(keyCode: 19, label: "2", pan: -0.66, category: .alpha, v1Code: 3, w3cCode: "Digit2"),
        KeyInfo(keyCode: 20, label: "3", pan: -0.52, category: .alpha, v1Code: 4, w3cCode: "Digit3"),
        KeyInfo(keyCode: 21, label: "4", pan: -0.38, category: .alpha, v1Code: 5, w3cCode: "Digit4"),
        KeyInfo(keyCode: 23, label: "5", pan: -0.24, category: .alpha, v1Code: 6, w3cCode: "Digit5"),
        KeyInfo(keyCode: 22, label: "6", pan: -0.10, category: .alpha, v1Code: 7, w3cCode: "Digit6"),
        KeyInfo(keyCode: 26, label: "7", pan: 0.04, category: .alpha, v1Code: 8, w3cCode: "Digit7"),
        KeyInfo(keyCode: 28, label: "8", pan: 0.18, category: .alpha, v1Code: 9, w3cCode: "Digit8"),
        KeyInfo(keyCode: 25, label: "9", pan: 0.32, category: .alpha, v1Code: 10, w3cCode: "Digit9"),
        KeyInfo(keyCode: 29, label: "0", pan: 0.46, category: .alpha, v1Code: 11, w3cCode: "Digit0"),
        KeyInfo(keyCode: 27, label: "-", pan: 0.60, category: .alpha, v1Code: 12, w3cCode: "Minus"),
        KeyInfo(keyCode: 24, label: "=", pan: 0.74, category: .alpha, v1Code: 13, w3cCode: "Equal"),
        KeyInfo(keyCode: 51, label: "⌫", pan: 0.92, category: .backspace, v1Code: 14, w3cCode: "Backspace"),

        // QWERTY Row
        KeyInfo(keyCode: 48, label: "⇥", pan: -0.90, category: .modifier, v1Code: 15, w3cCode: "Tab"),
        KeyInfo(keyCode: 12, label: "Q", pan: -0.74, category: .alpha, v1Code: 16, w3cCode: "KeyQ"),
        KeyInfo(keyCode: 13, label: "W", pan: -0.60, category: .alpha, v1Code: 17, w3cCode: "KeyW"),
        KeyInfo(keyCode: 14, label: "E", pan: -0.46, category: .alpha, v1Code: 18, w3cCode: "KeyE"),
        KeyInfo(keyCode: 15, label: "R", pan: -0.32, category: .alpha, v1Code: 19, w3cCode: "KeyR"),
        KeyInfo(keyCode: 17, label: "T", pan: -0.18, category: .alpha, v1Code: 20, w3cCode: "KeyT"),
        KeyInfo(keyCode: 16, label: "Y", pan: -0.04, category: .alpha, v1Code: 21, w3cCode: "KeyY"),
        KeyInfo(keyCode: 32, label: "U", pan: 0.10, category: .alpha, v1Code: 22, w3cCode: "KeyU"),
        KeyInfo(keyCode: 34, label: "I", pan: 0.24, category: .alpha, v1Code: 23, w3cCode: "KeyI"),
        KeyInfo(keyCode: 31, label: "O", pan: 0.38, category: .alpha, v1Code: 24, w3cCode: "KeyO"),
        KeyInfo(keyCode: 35, label: "P", pan: 0.52, category: .alpha, v1Code: 25, w3cCode: "KeyP"),
        KeyInfo(keyCode: 33, label: "[", pan: 0.66, category: .alpha, v1Code: 26, w3cCode: "BracketLeft"),
        KeyInfo(keyCode: 30, label: "]", pan: 0.80, category: .alpha, v1Code: 27, w3cCode: "BracketRight"),
        KeyInfo(keyCode: 42, label: "\\", pan: 0.94, category: .alpha, v1Code: 43, w3cCode: "Backslash"),

        // Home Row
        KeyInfo(keyCode: 57, label: "⇪", pan: -0.90, category: .modifier, v1Code: 58, w3cCode: "CapsLock"),
        KeyInfo(keyCode: 0, label: "A", pan: -0.70, category: .alpha, v1Code: 30, w3cCode: "KeyA"),
        KeyInfo(keyCode: 1, label: "S", pan: -0.56, category: .alpha, v1Code: 31, w3cCode: "KeyS"),
        KeyInfo(keyCode: 2, label: "D", pan: -0.42, category: .alpha, v1Code: 32, w3cCode: "KeyD"),
        KeyInfo(keyCode: 3, label: "F", pan: -0.28, category: .alpha, v1Code: 33, w3cCode: "KeyF"),
        KeyInfo(keyCode: 5, label: "G", pan: -0.14, category: .alpha, v1Code: 34, w3cCode: "KeyG"),
        KeyInfo(keyCode: 4, label: "H", pan: 0.00, category: .alpha, v1Code: 35, w3cCode: "KeyH"),
        KeyInfo(keyCode: 38, label: "J", pan: 0.14, category: .alpha, v1Code: 36, w3cCode: "KeyJ"),
        KeyInfo(keyCode: 40, label: "K", pan: 0.28, category: .alpha, v1Code: 37, w3cCode: "KeyK"),
        KeyInfo(keyCode: 37, label: "L", pan: 0.42, category: .alpha, v1Code: 38, w3cCode: "KeyL"),
        KeyInfo(keyCode: 41, label: ";", pan: 0.56, category: .alpha, v1Code: 39, w3cCode: "Semicolon"),
        KeyInfo(keyCode: 39, label: "'", pan: 0.70, category: .alpha, v1Code: 40, w3cCode: "Quote"),
        KeyInfo(keyCode: 36, label: "⏎", pan: 0.88, category: .enter, v1Code: 28, w3cCode: "Enter"),

        // Bottom Alpha Row
        KeyInfo(keyCode: 56, label: "⇧", pan: -0.88, category: .shift, v1Code: 42, w3cCode: "ShiftLeft"),
        KeyInfo(keyCode: 6, label: "Z", pan: -0.64, category: .alpha, v1Code: 44, w3cCode: "KeyZ"),
        KeyInfo(keyCode: 7, label: "X", pan: -0.50, category: .alpha, v1Code: 45, w3cCode: "KeyX"),
        KeyInfo(keyCode: 8, label: "C", pan: -0.36, category: .alpha, v1Code: 46, w3cCode: "KeyC"),
        KeyInfo(keyCode: 9, label: "V", pan: -0.22, category: .alpha, v1Code: 47, w3cCode: "KeyV"),
        KeyInfo(keyCode: 11, label: "B", pan: -0.08, category: .alpha, v1Code: 48, w3cCode: "KeyB"),
        KeyInfo(keyCode: 45, label: "N", pan: 0.06, category: .alpha, v1Code: 49, w3cCode: "KeyN"),
        KeyInfo(keyCode: 46, label: "M", pan: 0.20, category: .alpha, v1Code: 50, w3cCode: "KeyM"),
        KeyInfo(keyCode: 43, label: ",", pan: 0.34, category: .alpha, v1Code: 51, w3cCode: "Comma"),
        KeyInfo(keyCode: 47, label: ".", pan: 0.48, category: .alpha, v1Code: 52, w3cCode: "Period"),
        KeyInfo(keyCode: 44, label: "/", pan: 0.62, category: .alpha, v1Code: 53, w3cCode: "Slash"),
        KeyInfo(keyCode: 60, label: "⇧", pan: 0.86, category: .shift, v1Code: 54, w3cCode: "ShiftRight"),

        // Modifier / Spacebar Row
        KeyInfo(keyCode: 63, label: "fn", pan: -0.94, category: .modifier, v1Code: nil, w3cCode: "Fn"),
        KeyInfo(keyCode: 59, label: "⌃", pan: -0.82, category: .modifier, v1Code: 29, w3cCode: "ControlLeft"),
        KeyInfo(keyCode: 58, label: "⌥", pan: -0.68, category: .modifier, v1Code: 56, w3cCode: "AltLeft"),
        KeyInfo(keyCode: 55, label: "⌘", pan: -0.52, category: .modifier, v1Code: 3675, w3cCode: "MetaLeft"),
        KeyInfo(keyCode: 49, label: "Space", pan: 0.0, category: .space, v1Code: 57, w3cCode: "Space"),
        KeyInfo(keyCode: 54, label: "⌘", pan: 0.44, category: .modifier, v1Code: 3676, w3cCode: "MetaRight"),
        KeyInfo(keyCode: 61, label: "⌥", pan: 0.58, category: .modifier, v1Code: 3640, w3cCode: "AltRight"),
        KeyInfo(keyCode: 62, label: "⌃", pan: 0.68, category: .modifier, v1Code: 3613, w3cCode: "ControlRight"),

        // Arrow Keys & Navigation
        KeyInfo(keyCode: 123, label: "←", pan: 0.74, category: .alpha, v1Code: 57419, w3cCode: "ArrowLeft"),
        KeyInfo(keyCode: 126, label: "↑", pan: 0.84, category: .alpha, v1Code: 57416, w3cCode: "ArrowUp"),
        KeyInfo(keyCode: 125, label: "↓", pan: 0.84, category: .alpha, v1Code: 57424, w3cCode: "ArrowDown"),
        KeyInfo(keyCode: 124, label: "→", pan: 0.94, category: .alpha, v1Code: 57421, w3cCode: "ArrowRight"),
        KeyInfo(keyCode: 117, label: "⌦", pan: 0.90, category: .backspace, v1Code: 57427, w3cCode: "Delete"),

        // Function Row
        KeyInfo(keyCode: 122, label: "F1", pan: -0.82, category: .alpha, v1Code: 59, w3cCode: "F1"),
        KeyInfo(keyCode: 120, label: "F2", pan: -0.68, category: .alpha, v1Code: 60, w3cCode: "F2"),
        KeyInfo(keyCode: 99, label: "F3", pan: -0.54, category: .alpha, v1Code: 61, w3cCode: "F3"),
        KeyInfo(keyCode: 118, label: "F4", pan: -0.40, category: .alpha, v1Code: 62, w3cCode: "F4"),
        KeyInfo(keyCode: 96, label: "F5", pan: -0.26, category: .alpha, v1Code: 63, w3cCode: "F5"),
        KeyInfo(keyCode: 97, label: "F6", pan: -0.12, category: .alpha, v1Code: 64, w3cCode: "F6"),
        KeyInfo(keyCode: 98, label: "F7", pan: 0.02, category: .alpha, v1Code: 65, w3cCode: "F7"),
        KeyInfo(keyCode: 100, label: "F8", pan: 0.16, category: .alpha, v1Code: 66, w3cCode: "F8"),
        KeyInfo(keyCode: 101, label: "F9", pan: 0.30, category: .alpha, v1Code: 67, w3cCode: "F9"),
        KeyInfo(keyCode: 109, label: "F10", pan: 0.44, category: .alpha, v1Code: 68, w3cCode: "F10"),
        KeyInfo(keyCode: 103, label: "F11", pan: 0.58, category: .alpha, v1Code: 87, w3cCode: "F11"),
        KeyInfo(keyCode: 111, label: "F12", pan: 0.72, category: .alpha, v1Code: 88, w3cCode: "F12"),

        // Numpad Return (for external keyboards)
        KeyInfo(keyCode: 76, label: "⌤", pan: 0.96, category: .enter, v1Code: 3612, w3cCode: "NumpadEnter")
    ]

    private static let byKeyCode: [UInt16: KeyInfo] = {
        Dictionary(uniqueKeysWithValues: allKeys.map { ($0.keyCode, $0) })
    }()

    private static let byV1Code: [Int: UInt16] = {
        var map: [Int: UInt16] = [:]
        for info in allKeys {
            if let v1 = info.v1Code {
                map[v1] = info.keyCode
            }
        }
        // Common alternate V1 extended codes used by some Mechvibes packs
        map[61003] = 123 // ArrowLeft
        map[61000] = 126 // ArrowUp
        map[61008] = 125 // ArrowDown
        map[61005] = 124 // ArrowRight
        map[61011] = 117 // Delete
        return map
    }()

    private static let byW3CCode: [String: UInt16] = {
        var map: [String: UInt16] = [:]
        for info in allKeys {
            map[info.w3cCode.lowercased()] = info.keyCode
        }
        // Common aliases in MechvibesDX V2 packs
        map["return"] = 36
        map["spacebar"] = 49
        map["lshift"] = 56
        map["rshift"] = 60
        map["lcontrol"] = 59
        map["rcontrol"] = 62
        map["lalt"] = 58
        map["ralt"] = 61
        map["lmeta"] = 55
        map["rmeta"] = 54
        map["osleft"] = 55
        map["osright"] = 54
        return map
    }()

    static func info(for keyCode: UInt16) -> KeyInfo {
        if let found = byKeyCode[keyCode] {
            return found
        }
        return KeyInfo(
            keyCode: keyCode,
            label: "K\(keyCode)",
            pan: 0.0,
            category: .alpha,
            v1Code: nil,
            w3cCode: "Unidentified"
        )
    }

    static func macKeyCode(fromV1Code code: Int) -> UInt16? {
        byV1Code[code]
    }

    static func macKeyCode(fromW3CCode name: String) -> UInt16? {
        byW3CCode[name.lowercased()]
    }
}
