import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Describes why KeyClack is currently silent, or nil if actively playing sounds.
enum MuteReason: Equatable {
    case manualOff
    case microphoneActive
    case excludedApp(String)

    var badgeText: String {
        switch self {
        case .manualOff:
            return "Muted"
        case .microphoneActive:
            return "Auto-Muted · Mic Active"
        case .excludedApp(let appName):
            return "Auto-Muted · \(appName)"
        }
    }
}

/// Central observable state coordinating audio playback, global keyboard capture,
/// Smart Mute monitors, imported sound packs, and persisted user settings.
@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            settings.save()
            applySettingsToServices()
        }
    }

    @Published var hasInputPermission: Bool = KeyEventMonitor.hasPermission
    @Published var isMicrophoneActive: Bool = false
    @Published var frontmostBundleID: String?
    @Published var frontmostAppName: String?

    @Published var importedPacks: [ImportedSoundPack] = []
    @Published var importErrorMessage: String?
    @Published var statusToast: String?
    @Published var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled

    // Menu bar popover UI state (stored here as @Published so building with standalone
    // macOS Command Line Tools never requires the Xcode-only SwiftUIMacros plugin)
    @Published var selectedTab: MenuTab = .switches
    @Published var runningApps: [ExcludedApp] = []

    // Live keyboard visualizer state
    @Published var pressedKeyCodes: Set<UInt16> = []
    @Published var lastActivePan: Float = 0.0
    @Published var lastKeyLabel: String = ""

    private let audioEngine = AudioEngine()
    private let keyMonitor = KeyEventMonitor()
    private let hotKeyManager = GlobalHotKeyManager()
    private let micMonitor = MicrophoneMonitor()
    private let appMonitor = ActiveAppMonitor()

    private var loadedPacksCache: [String: LoadedSoundPack] = [:]

    var muteReason: MuteReason? {
        if !settings.isEnabled {
            return .manualOff
        }
        if settings.autoMuteOnMicrophone && isMicrophoneActive {
            return .microphoneActive
        }
        if let bundleID = frontmostBundleID,
           let matched = settings.excludedApps.first(where: { $0.bundleIdentifier == bundleID }) {
            return .excludedApp(matched.displayName)
        }
        return nil
    }

    var isActivelyPlaying: Bool {
        muteReason == nil && hasInputPermission
    }

    var activeProfileTitle: String {
        switch settings.activeProfile {
        case .builtIn(let sw):
            return sw.displayName
        case .imported(let id):
            return importedPacks.first(where: { $0.id == id })?.name ?? "Custom Pack"
        }
    }

    init() {
        let loaded = AppSettings.load()
        self.settings = loaded
        self.importedPacks = SoundPackImporter.listImportedPacks()

        configureCallbacks()
        applySettingsToServices()
        activateCurrentProfile()

        keyMonitor.start()
        micMonitor.start()
        appMonitor.start()
    }

    private func configureCallbacks() {
        let engineRef = self.audioEngine

        keyMonitor.onPermissionChanged = { [weak self] granted in
            Task { @MainActor in
                self?.hasInputPermission = granted
            }
        }

        // Fire audio immediately with zero MainActor hop, then update live mini keyboard UI
        keyMonitor.onKeyEvent = { [weak self] keyCode, isDown in
            engineRef.playKeyIfUnmuted(keyCode: keyCode, isDown: isDown)
            let info = KeyLayoutMap.info(for: keyCode)
            Task { @MainActor in
                guard let self else { return }
                if isDown {
                    self.pressedKeyCodes.insert(keyCode)
                    self.lastActivePan = info.pan
                    self.lastKeyLabel = info.label
                } else {
                    self.pressedKeyCodes.remove(keyCode)
                }
            }
        }

        hotKeyManager.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.toggleEnabled()
            }
        }

        micMonitor.onMicrophoneActivityChanged = { [weak self] active in
            Task { @MainActor in
                guard let self else { return }
                self.isMicrophoneActive = active
                self.syncMuteState()
            }
        }

        appMonitor.onFrontmostAppChanged = { [weak self] bundleID, appName in
            Task { @MainActor in
                guard let self else { return }
                self.frontmostBundleID = bundleID
                self.frontmostAppName = appName
                self.syncMuteState()
            }
        }
    }

    private func syncMuteState() {
        audioEngine.setMuted(muteReason != nil)
    }

    private func applySettingsToServices() {
        audioEngine.updateParameters(from: settings)
        keyMonitor.ignoreKeyRepeat = settings.ignoreKeyRepeat
        hotKeyManager.register(preset: settings.globalHotKey)
        syncMuteState()
    }

    private func activateCurrentProfile() {
        switch settings.activeProfile {
        case .builtIn(let sw):
            audioEngine.selectBuiltIn(sw)
        case .imported(let id):
            if let cached = loadedPacksCache[id] {
                audioEngine.selectImportedPack(cached)
            } else if let pack = try? SoundPackImporter.loadSavedPack(id: id) {
                loadedPacksCache[id] = pack
                audioEngine.selectImportedPack(pack)
            } else {
                // Saved pack was removed externally; fall back gracefully
                settings.activeProfile = .builtIn(.holyPanda)
                audioEngine.selectBuiltIn(.holyPanda)
            }
        }
    }

    // MARK: - User Actions

    func toggleEnabled() {
        settings.isEnabled.toggle()
        if settings.isEnabled {
            audioEngine.playKey(keyCode: 49, isDown: true)
        }
    }

    func selectBuiltIn(_ sw: BuiltInSwitch, audition: Bool = true) {
        settings.activeProfile = .builtIn(sw)
        audioEngine.selectBuiltIn(sw)
        if audition {
            audioEngine.playPreviewRhythm()
        }
    }

    func selectImportedPack(id: String, audition: Bool = true) {
        do {
            let pack: LoadedSoundPack
            if let cached = loadedPacksCache[id] {
                pack = cached
            } else {
                pack = try SoundPackImporter.loadSavedPack(id: id)
                loadedPacksCache[id] = pack
            }
            settings.activeProfile = .imported(id)
            audioEngine.selectImportedPack(pack)
            if audition {
                audioEngine.playPreviewRhythm()
            }
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func auditionCurrentProfile() {
        audioEngine.playPreviewRhythm()
    }

    func triggerVirtualKey(keyCode: UInt16) {
        let info = KeyLayoutMap.info(for: keyCode)
        pressedKeyCodes.insert(keyCode)
        lastActivePan = info.pan
        lastKeyLabel = info.label
        audioEngine.playKey(keyCode: keyCode, isDown: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(65)) { [weak self] in
            self?.pressedKeyCodes.remove(keyCode)
            self?.audioEngine.playKey(keyCode: keyCode, isDown: false)
        }
    }

    func requestInputMonitoringPermission() {
        KeyEventMonitor.requestPermission()
        KeyEventMonitor.openInputMonitoringSettings()
        keyMonitor.start()
    }

    func resetAcousticTuning() {
        settings.volume = 0.78
        settings.pitchShift = 1.0
        settings.stereoWidth = 0.72
        settings.upstrokeVolume = 0.70
        settings.enableUpstroke = true
        settings.enableStereoPanning = true
        settings.enableMicroVariation = true
        settings.ignoreKeyRepeat = true
        showToast("Acoustic settings reset to defaults")
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginManager.isEnabled
        } catch {
            launchAtLogin = LaunchAtLoginManager.isEnabled
            importErrorMessage = error.localizedDescription
        }
    }

    func refreshRunningApps() {
        runningApps = ActiveAppMonitor.runningRegularApps()
    }

    func addExcludedApp(_ app: ExcludedApp) {
        if !settings.excludedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            settings.excludedApps.append(app)
        }
    }

    func removeExcludedApp(bundleID: String) {
        settings.excludedApps.removeAll { $0.bundleIdentifier == bundleID }
    }

    /// Presents a native macOS file/folder picker for Mechvibes V1/V2 packs, ZIPs, or WAV folders.
    func presentImportPackPanel() {
        importErrorMessage = nil
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Import Sound Pack (Mechvibes V1/V2, ZIP, or Audio Folder)"
        panel.message = "Choose a Mechvibes .zip archive, an extracted sound pack folder, a config.json file, or any folder of WAV/MP3/FLAC key sounds."
        panel.prompt = "Import Pack"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, .json, .folder]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let loaded = try SoundPackImporter.importPack(from: url)
            loadedPacksCache[loaded.metadata.id] = loaded
            importedPacks = SoundPackImporter.listImportedPacks()
            settings.activeProfile = .imported(loaded.metadata.id)
            audioEngine.selectImportedPack(loaded)
            audioEngine.playPreviewRhythm()
            showToast("Imported \"\(loaded.metadata.name)\"")
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func deleteImportedPack(_ pack: ImportedSoundPack) {
        SoundPackImporter.deletePack(id: pack.id)
        loadedPacksCache.removeValue(forKey: pack.id)
        importedPacks = SoundPackImporter.listImportedPacks()

        if settings.activeProfile == .imported(pack.id) {
            selectBuiltIn(.holyPanda, audition: false)
        }
        showToast("Removed \"\(pack.name)\"")
    }

    private func showToast(_ message: String) {
        statusToast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) { [weak self] in
            if self?.statusToast == message {
                self?.statusToast = nil
            }
        }
    }
}
