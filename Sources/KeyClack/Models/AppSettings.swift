import Foundation
import Carbon

/// Curated global shortcut presets for instant mute/unmute from any app.
enum HotKeyPreset: String, Codable, CaseIterable, Identifiable {
    case ctrlOptCmdK = "ctrl_opt_cmd_k"
    case ctrlOptCmdM = "ctrl_opt_cmd_m"
    case ctrlShiftM = "ctrl_shift_m"
    case optShiftK = "opt_shift_k"
    case disabled = "disabled"

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .ctrlOptCmdK: return "⌃ ⌥ ⌘ K"
        case .ctrlOptCmdM: return "⌃ ⌥ ⌘ M"
        case .ctrlShiftM: return "⌃ ⇧ M"
        case .optShiftK: return "⌥ ⇧ K"
        case .disabled: return "Disabled"
        }
    }

    /// Carbon virtual key code.
    var keyCode: UInt32 {
        switch self {
        case .ctrlOptCmdK, .optShiftK: return UInt32(kVK_ANSI_K)
        case .ctrlOptCmdM, .ctrlShiftM: return UInt32(kVK_ANSI_M)
        case .disabled: return 0
        }
    }

    /// Carbon modifier flags.
    var carbonModifiers: UInt32 {
        switch self {
        case .ctrlOptCmdK, .ctrlOptCmdM:
            return UInt32(controlKey | optionKey | cmdKey)
        case .ctrlShiftM:
            return UInt32(controlKey | shiftKey)
        case .optShiftK:
            return UInt32(optionKey | shiftKey)
        case .disabled:
            return 0
        }
    }
}

/// Excluded application entry for per-app Smart Mute.
struct ExcludedApp: Codable, Identifiable, Hashable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String

    static let commonSuggestions: [ExcludedApp] = [
        ExcludedApp(bundleIdentifier: "us.zoom.xos", displayName: "Zoom"),
        ExcludedApp(bundleIdentifier: "com.apple.FaceTime", displayName: "FaceTime"),
        ExcludedApp(bundleIdentifier: "com.hnc.Discord", displayName: "Discord"),
        ExcludedApp(bundleIdentifier: "com.microsoft.teams2", displayName: "Microsoft Teams"),
        ExcludedApp(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack"),
        ExcludedApp(bundleIdentifier: "com.obsproject.obs-studio", displayName: "OBS Studio"),
        ExcludedApp(bundleIdentifier: "com.apple.VoiceMemos", displayName: "Voice Memos")
    ]
}

/// Persistent user configuration for KeyClack.
struct AppSettings: Codable, Equatable {
    var isEnabled: Bool = true
    var activeProfile: ActiveProfileSelection = .builtIn(.holyPanda)

    // Sound & Acoustic Tuning
    var volume: Double = 0.78               // 0.0 ... 1.0
    var pitchShift: Double = 1.0            // 0.80 ... 1.25
    var stereoWidth: Double = 0.72          // 0.0 ... 1.0
    var upstrokeVolume: Double = 0.70       // 0.0 ... 1.0

    // Realism Toggles
    var enableUpstroke: Bool = true
    var enableStereoPanning: Bool = true
    var enableMicroVariation: Bool = true
    var ignoreKeyRepeat: Bool = true

    // Smart Mute & Workflow
    var autoMuteOnMicrophone: Bool = true
    var excludedApps: [ExcludedApp] = []
    var globalHotKey: HotKeyPreset = .ctrlOptCmdK

    private static let storageKey = "com.keyclack.app.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
