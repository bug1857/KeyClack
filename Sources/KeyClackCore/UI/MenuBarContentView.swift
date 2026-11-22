import SwiftUI

enum MenuTab: String, CaseIterable, Identifiable {
    case switches = "Switches"
    case tune = "Tune"
    case smartMute = "Smart Mute"

    var id: String { rawValue }
}

/// Main Klack-inspired macOS menu bar popover interface.
public struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self._appState = ObservedObject(wrappedValue: appState)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            if !appState.hasInputPermission {
                permissionBanner
                Divider()
            }

            if let errorMsg = appState.importErrorMessage {
                errorBanner(errorMsg)
                Divider()
            }

            if let toast = appState.statusToast {
                toastBanner(toast)
                Divider()
            }

            // Tab Switcher
            Picker("", selection: $appState.selectedTab) {
                ForEach(MenuTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Tab Body (explicit height required so macOS MenuBarExtra(.window) doesn't collapse ScrollView to 0)
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch appState.selectedTab {
                    case .switches:
                        switchesTab
                    case .tune:
                        tuneTab
                    case .smartMute:
                        smartMuteTab
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .frame(height: 430)

            Divider()
            footerSection
        }
        .frame(width: 384)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            appState.refreshRunningApps()
        }
        .onChange(of: appState.selectedTab) { tab in
            if tab == .smartMute {
                appState.refreshRunningApps()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(appState.isActivelyPlaying ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
                    .frame(width: 34, height: 34)
                Image(systemName: appState.isActivelyPlaying ? "keyboard" : "speaker.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(appState.isActivelyPlaying ? .accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("KeyClack")
                        .font(.system(size: 14, weight: .bold))
                    statusPill
                }
                Text(appState.activeProfileTitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { appState.settings.isEnabled },
                set: { newVal in
                    appState.settings.isEnabled = newVal
                    if newVal {
                        appState.triggerVirtualKey(keyCode: 49)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            if !appState.hasInputPermission {
                return ("Needs Permission", .orange)
            }
            if let reason = appState.muteReason {
                switch reason {
                case .manualOff:
                    return ("Muted", .secondary)
                case .microphoneActive:
                    return ("Call Mute", .orange)
                case .excludedApp:
                    return ("App Mute", .orange)
                }
            }
            return ("Live", .green)
        }()

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: - Banners

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(.orange)
                .font(.system(size: 15))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text("Enable Input Monitoring")
                    .font(.system(size: 12, weight: .semibold))
                Text("macOS requires Input Monitoring permission so KeyClack can hear physical key presses in other apps.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Grant Permission in System Settings") {
                    appState.requestInputMonitoringPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 12))
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                appState.importErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.10))
    }

    private func toastBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.10))
    }

    // MARK: - Tab 1: Switches & Sound Packs

    private var switchesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Built-In Switches Grid
            HStack {
                Text("BUILT-IN SWITCHES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    appState.auditionCurrentProfile()
                } label: {
                    Label("Test Sound", systemImage: "play.fill")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(BuiltInSwitch.allCases) { sw in
                    builtInSwitchCard(sw)
                }
            }

            // Master Volume Quick Slider
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Volume")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Text("\(Int(round(appState.settings.volume * 100)))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.settings.volume, in: 0...1)
                    .controlSize(.small)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))

            // Imported Mechvibes / Custom Packs
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CUSTOM & MECHVIBES PACKS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        appState.presentImportPackPanel()
                    } label: {
                        Label("Import Pack…", systemImage: "plus.circle.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                if appState.importedPacks.isEmpty {
                    Text("Supports Mechvibes V1 & V2 (.zip or folder) and plain WAV/MP3/M4A/FLAC folders.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                } else {
                    ForEach(appState.importedPacks) { pack in
                        importedPackRow(pack)
                    }
                }
            }

            // Interactive Live Key Strip
            MiniKeyboardView(appState: appState)
        }
    }

    private func builtInSwitchCard(_ sw: BuiltInSwitch) -> some View {
        let isSelected = appState.settings.activeProfile == .builtIn(sw)
        let rgb = sw.accentRGB
        let accent = Color(red: rgb.0, green: rgb.1, blue: rgb.2)

        return Button {
            appState.selectBuiltIn(sw, audition: true)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accent)
                        .frame(width: 9, height: 9)
                    Text(sw.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(accent)
                    }
                }

                Text(sw.category.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(accent)

                Text(sw.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.25 : 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    private func importedPackRow(_ pack: ImportedSoundPack) -> some View {
        let isSelected = appState.settings.activeProfile == .imported(pack.id)

        return HStack(spacing: 8) {
            Button {
                appState.selectImportedPack(id: pack.id, audition: true)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "waveform")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pack.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("\(pack.formatDescription) · \(pack.hasKeyUpSounds ? "Down + Up" : "Down only")")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                appState.deleteImportedPack(pack)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove sound pack")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: 0.9)
        )
    }

    // MARK: - Tab 2: Acoustic Tuning

    private var tuneTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            tuningSlider(
                title: "Master Volume",
                valueText: "\(Int(round(appState.settings.volume * 100)))%",
                value: $appState.settings.volume,
                range: 0...1
            )

            tuningSlider(
                title: "Tone / Pitch",
                valueText: pitchLabel(appState.settings.pitchShift),
                value: $appState.settings.pitchShift,
                range: 0.80...1.25
            )

            tuningSlider(
                title: "Stereo Spatial Width",
                valueText: "\(Int(round(appState.settings.stereoWidth * 100)))%",
                value: $appState.settings.stereoWidth,
                range: 0...1
            )
            .disabled(!appState.settings.enableStereoPanning)
            .opacity(appState.settings.enableStereoPanning ? 1 : 0.45)

            tuningSlider(
                title: "Key-Up Release Level",
                valueText: "\(Int(round(appState.settings.upstrokeVolume * 100)))%",
                value: $appState.settings.upstrokeVolume,
                range: 0...1
            )
            .disabled(!appState.settings.enableUpstroke)
            .opacity(appState.settings.enableUpstroke ? 1 : 0.45)

            VStack(spacing: 8) {
                realismToggle(
                    title: "Key-Up (Release) Sounds",
                    subtitle: "Play housing top-out sound when releasing a key",
                    isOn: $appState.settings.enableUpstroke
                )
                Divider()
                realismToggle(
                    title: "Spatial Stereo Panning",
                    subtitle: "Left keys sound left, right keys sound right",
                    isOn: $appState.settings.enableStereoPanning
                )
                Divider()
                realismToggle(
                    title: "Organic Micro-Variation",
                    subtitle: "Subtle pitch & velocity humanization per stroke",
                    isOn: $appState.settings.enableMicroVariation
                )
                Divider()
                realismToggle(
                    title: "Ignore Key Repeat",
                    subtitle: "Holding a key down won't spam mechanical clicks",
                    isOn: $appState.settings.ignoreKeyRepeat
                )
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))

            HStack {
                Button("Reset Defaults") {
                    appState.resetAcousticTuning()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    appState.auditionCurrentProfile()
                } label: {
                    Label("Play Typing Test", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func tuningSlider(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private func realismToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    private func pitchLabel(_ value: Double) -> String {
        if value < 0.96 {
            return String(format: "%.2f× (Thockier)", value)
        } else if value > 1.04 {
            return String(format: "%.2f× (Clackier)", value)
        }
        return "1.00× (Natural)"
    }

    // MARK: - Tab 3: Smart Mute & System

    private var smartMuteTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Auto-Mute During Calls / Mic Activity
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Mute When Mic Is Active")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Silences key clicks during Zoom, Meet, FaceTime, or dictation.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $appState.settings.autoMuteOnMicrophone)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isMicrophoneActive ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text(appState.isMicrophoneActive ? "Microphone currently in use" : "Microphone idle")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))

            // Global Hotkey & Launch at Login
            VStack(spacing: 10) {
                HStack {
                    Text("Global Mute Shortcut")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Picker("", selection: $appState.settings.globalHotKey) {
                        ForEach(HotKeyPreset.allCases) { preset in
                            Text(preset.displayLabel).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 122)
                    .controlSize(.small)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Launch at Login")
                            .font(.system(size: 12, weight: .medium))
                        Text(LaunchAtLoginManager.isRunningFromAppBundle
                             ? "Start KeyClack quietly in your menu bar"
                             : "Available once installed as KeyClack.app")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.toggleLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))

            // Per-App Smart Mute List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AUTO-MUTE IN SPECIFIC APPS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Menu {
                        if !appState.runningApps.isEmpty {
                            Section(header: Text("Currently Running Apps")) {
                                ForEach(appState.runningApps) { app in
                                    Button(app.displayName) {
                                        appState.addExcludedApp(app)
                                    }
                                }
                            }
                        }
                        Section(header: Text("Common Call & Recording Apps")) {
                            ForEach(ExcludedApp.commonSuggestions) { app in
                                Button(app.displayName) {
                                    appState.addExcludedApp(app)
                                }
                            }
                        }
                        Divider()
                        Button("Refresh Running Apps") {
                            appState.refreshRunningApps()
                        }
                    } label: {
                        Label("Add App", systemImage: "plus")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if appState.settings.excludedApps.isEmpty {
                    Text("No apps excluded. Click \"Add App\" to mute KeyClack automatically whenever a chosen app is in front.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                } else {
                    ForEach(appState.settings.excludedApps) { app in
                        HStack {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(app.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                Text(app.bundleIdentifier)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                appState.removeExcludedApp(bundleID: app.bundleIdentifier)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if appState.settings.globalHotKey != .disabled {
                Text("Mute: \(appState.settings.globalHotKey.displayLabel)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("KeyClack v1.0")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Quit KeyClack") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
