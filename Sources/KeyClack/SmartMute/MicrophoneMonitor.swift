import Foundation
import CoreAudio

/// Detects when any macOS microphone / audio input device is actively in use
/// (e.g. Zoom, Google Meet, FaceTime, Discord, Dictation) using CoreAudio HAL queries.
/// Does NOT record audio and does NOT trigger macOS's Microphone privacy prompt.
final class MicrophoneMonitor {
    var onMicrophoneActivityChanged: ((Bool) -> Void)?

    private let monitorQueue = DispatchQueue(label: "com.keyclack.mic.monitor", qos: .utility)
    private var observedDeviceIDs: [AudioDeviceID] = []
    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceRunningListenerBlock: AudioObjectPropertyListenerBlock?
    private var lastKnownActive: Bool = false
    private var isStarted: Bool = false

    func start() {
        monitorQueue.async { [weak self] in
            guard let self, !self.isStarted else { return }
            self.isStarted = true
            self.installDeviceListListener()
            self.refreshObservedInputDevices()
            self.evaluateMicrophoneState(forceNotify: true)
        }
    }

    func stop() {
        monitorQueue.async { [weak self] in
            guard let self, self.isStarted else { return }
            self.isStarted = false
            self.removeDeviceListeners()
            if let block = self.deviceListListenerBlock {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDevices,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                _ = AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    self.monitorQueue,
                    block
                )
                self.deviceListListenerBlock = nil
            }
        }
    }

    deinit {
        stop()
    }

    private func installDeviceListListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.refreshObservedInputDevices()
            self.evaluateMicrophoneState(forceNotify: false)
        }
        self.deviceListListenerBlock = block

        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            monitorQueue,
            block
        )
    }

    private func refreshObservedInputDevices() {
        removeDeviceListeners()
        let inputDevices = Self.fetchInputAudioDevices()
        observedDeviceIDs = inputDevices

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.evaluateMicrophoneState(forceNotify: false)
        }
        self.deviceRunningListenerBlock = block

        for deviceID in inputDevices {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectAddPropertyListenerBlock(deviceID, &address, monitorQueue, block)
        }
    }

    private func removeDeviceListeners() {
        guard let block = deviceRunningListenerBlock else { return }
        for deviceID in observedDeviceIDs {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectRemovePropertyListenerBlock(deviceID, &address, monitorQueue, block)
        }
        observedDeviceIDs.removeAll()
        deviceRunningListenerBlock = nil
    }

    private func evaluateMicrophoneState(forceNotify: Bool) {
        let isActive = observedDeviceIDs.contains { Self.isInputRunning(on: $0) }
        if forceNotify || isActive != lastKnownActive {
            lastKnownActive = isActive
            DispatchQueue.main.async { [weak self] in
                self?.onMicrophoneActivityChanged?(isActive)
            }
        }
    }

    // MARK: - CoreAudio HAL Queries

    private static func fetchInputAudioDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        return deviceIDs.filter { channelCount(for: $0, scope: kAudioDevicePropertyScopeInput) > 0 }
    }

    private static func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return 0
        }

        let rawPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawPtr.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, rawPtr) == noErr else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(
            rawPtr.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Checks whether a device's microphone input is actively running.
    /// Avoids false positives on combined USB headsets playing Spotify by checking input scope
    /// when a device exposes both input and output channels.
    private static func isInputRunning(on deviceID: AudioDeviceID) -> Bool {
        let outputChannels = channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput)

        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        if outputChannels == 0 {
            // Pure input device (MacBook built-in mic, AirPods input, standalone USB mic)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr {
                return running != 0
            }
            return false
        } else {
            // Combined duplex device: specifically inspect input scope to ignore speaker-only playback
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &size, &running) == noErr {
                return running != 0
            }
            return false
        }
    }
}
