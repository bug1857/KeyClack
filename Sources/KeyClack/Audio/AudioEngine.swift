import Foundation
import AVFoundation

/// Ultra-low-latency polyphonic audio engine for mechanical keyboard playback.
/// Uses a 16-voice AVAudioPlayerNode pool with canonical 48 kHz stereo buffers,
/// zero-latency pitch micro-variation via linear resampling, equal-power stereo panning,
/// and subtle Haas interaural timing cues.
final class AudioEngine {
    static let sampleRate: Double = 48_000.0
    private let voiceCount = 16

    private let audioQueue = DispatchQueue(label: "com.keyclack.audio.engine", qos: .userInteractive)
    private let engine = AVAudioEngine()
    private let stereoFormat: AVAudioFormat
    private var players: [AVAudioPlayerNode] = []
    private var nextVoiceIndex: Int = 0
    private var cycleCounter: Int = 0

    // Cached sound banks (mutated & read strictly on audioQueue)
    private var builtInCache: [BuiltInSwitch: SynthesizedSwitchBank] = [:]
    private var activeBuiltIn: BuiltInSwitch? = .holyPanda
    private var activeImportedPack: LoadedSoundPack?

    // Atomic-like snapshot of playback parameters updated from main thread onto audioQueue
    private var isMuted: Bool = false
    private var volume: Float = 0.78
    private var pitchShift: Float = 1.0
    private var stereoWidth: Float = 0.72
    private var upstrokeVolume: Float = 0.70
    private var enableUpstroke: Bool = true
    private var enableStereoPanning: Bool = true
    private var enableMicroVariation: Bool = true

    private var configObserver: NSObjectProtocol?

    init() {
        self.stereoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 2,
            interleaved: false
        )!

        setupGraph()
        observeHardwareChanges()

        // Pre-synthesize the default switch profile immediately
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.builtInCache[.holyPanda] = SwitchSynthesizer.synthesizeBank(for: .holyPanda)
            self.startEngineIfNeeded()
        }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        engine.stop()
    }

    private func setupGraph() {
        players.removeAll()
        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: stereoFormat)
            players.append(player)
        }
        engine.prepare()
    }

    private func observeHardwareChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.audioQueue.async { [weak self] in
                self?.restartAfterHardwareChange()
            }
        }
    }

    private func restartAfterHardwareChange() {
        for player in players {
            player.stop()
        }
        engine.stop()
        engine.prepare()
        startEngineIfNeeded()
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            for player in players {
                if !player.isPlaying {
                    player.play()
                }
            }
        } catch {
            // Engine will retry automatically on next key event
        }
    }

    /// Sets the live mute gate (combines manual toggle, active microphone, and excluded apps).
    func setMuted(_ muted: Bool) {
        audioQueue.async { [weak self] in
            self?.isMuted = muted
        }
    }

    /// Updates live acoustic tuning parameters from AppSettings.
    func updateParameters(from settings: AppSettings) {
        let vol = Float(settings.volume)
        let pitch = Float(settings.pitchShift)
        let width = Float(settings.stereoWidth)
        let upVol = Float(settings.upstrokeVolume)
        let upEnabled = settings.enableUpstroke
        let panEnabled = settings.enableStereoPanning
        let microVar = settings.enableMicroVariation

        audioQueue.async { [weak self] in
            guard let self else { return }
            self.volume = vol
            self.pitchShift = pitch
            self.stereoWidth = width
            self.upstrokeVolume = upVol
            self.enableUpstroke = upEnabled
            self.enableStereoPanning = panEnabled
            self.enableMicroVariation = microVar
        }
    }

    /// Activates one of the 6 built-in physically modeled switches.
    func selectBuiltIn(_ sw: BuiltInSwitch) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            if self.builtInCache[sw] == nil {
                self.builtInCache[sw] = SwitchSynthesizer.synthesizeBank(for: sw)
            }
            self.activeBuiltIn = sw
            self.activeImportedPack = nil
        }
    }

    /// Activates a loaded custom / Mechvibes sound pack.
    func selectImportedPack(_ pack: LoadedSoundPack) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.activeImportedPack = pack
            self.activeBuiltIn = nil
        }
    }

    /// Plays a key sound immediately unless KeyClack is muted or Smart-Muted.
    func playKeyIfUnmuted(keyCode: UInt16, isDown: Bool) {
        playKey(keyCode: keyCode, isDown: isDown, respectMute: true)
    }

    /// Plays a key down or key up mechanical switch sound with <3 ms latency.
    func playKey(keyCode: UInt16, isDown: Bool, respectMute: Bool = false) {
        let info = KeyLayoutMap.info(for: keyCode)
        audioQueue.async { [weak self] in
            guard let self else { return }
            if respectMute && self.isMuted {
                return
            }
            if !isDown && !self.enableUpstroke {
                return
            }
            self.startEngineIfNeeded()
            guard self.engine.isRunning else { return }

            self.cycleCounter &+= 1
            let clip: SampleClip?

            if let pack = self.activeImportedPack {
                clip = pack.clip(
                    for: keyCode,
                    category: info.category,
                    isDown: isDown,
                    cycleIndex: self.cycleCounter
                )
            } else if let builtIn = self.activeBuiltIn,
                      let bank = self.builtInCache[builtIn] {
                let pool = isDown ? bank.downClips[info.category] : bank.upClips[info.category]
                if let pool, !pool.isEmpty {
                    clip = pool[self.cycleCounter % pool.count]
                } else {
                    clip = nil
                }
            } else {
                clip = nil
            }

            guard let clip, !clip.samples.isEmpty else { return }

            // Organic velocity & pitch micro-variation eliminates robotic repetition
            let pitchJitter: Float = self.enableMicroVariation ? Float.random(in: 0.976...1.024) : 1.0
            let ampJitter: Float = self.enableMicroVariation ? Float.random(in: 0.93...1.04) : 1.0
            let effectiveRate = max(0.65, min(1.55, self.pitchShift * pitchJitter))
            let strokeGain: Float = isDown ? 1.0 : self.upstrokeVolume
            let effectiveGain = self.volume * strokeGain * ampJitter

            guard effectiveGain > 0.001 else { return }

            // Spatial panning across MacBook physical keyboard width
            let rawPan = self.enableStereoPanning ? (info.pan * self.stereoWidth) : 0.0
            let clampedPan = max(-0.82, min(0.82, rawPan))

            guard let buffer = self.renderStereoBuffer(
                from: clip.samples,
                rate: effectiveRate,
                gain: effectiveGain,
                pan: clampedPan
            ) else {
                return
            }

            let voice = self.players[self.nextVoiceIndex]
            self.nextVoiceIndex = (self.nextVoiceIndex + 1) % self.voiceCount
            voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
            if !voice.isPlaying {
                voice.play()
            }
        }
    }

    /// Plays a short realistic typing phrase ("thock-thock-thock-SPACE-ENTER") for instant auditioning.
    func playPreviewRhythm() {
        let sequence: [(keyCode: UInt16, delayMs: Int, holdMs: Int)] = [
            (0, 0, 58),     // A (left)
            (3, 95, 55),    // F (left-mid)
            (38, 185, 54),  // J (right-mid)
            (40, 270, 52),  // K (right)
            (49, 380, 68),  // Space (center deep thock)
            (36, 515, 65)   // Enter (right stabilized)
        ]
        for step in sequence {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: .now() + .milliseconds(step.delayMs)
            ) { [weak self] in
                self?.playKey(keyCode: step.keyCode, isDown: true)
            }
            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: .now() + .milliseconds(step.delayMs + step.holdMs)
            ) { [weak self] in
                self?.playKey(keyCode: step.keyCode, isDown: false)
            }
        }
    }

    /// Resamples mono clip with zero-latency linear interpolation, equal-power stereo panning,
    /// and a subtle Haas interaural micro-delay (up to 0.25 ms) for natural keyboard spatialization.
    private func renderStereoBuffer(
        from mono: [Float],
        rate: Float,
        gain: Float,
        pan: Float
    ) -> AVAudioPCMBuffer? {
        let srcCount = mono.count
        guard srcCount > 1 else { return nil }

        let resampledLen = max(16, Int(Float(srcCount - 1) / rate))
        // Subtle Haas ITD: up to 12 samples (~0.25 ms at 48 kHz)
        let itdSamples = Int(round(abs(pan) * 12.0))
        let leftDelay = pan > 0 ? itdSamples : 0
        let rightDelay = pan < 0 ? itdSamples : 0
        let totalFrames = resampledLen + itdSamples

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: stereoFormat,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ),
        let leftPtr = buffer.floatChannelData?[0],
        let rightPtr = buffer.floatChannelData?[1] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(totalFrames)

        // Zero-fill leading/trailing Haas padding
        for i in 0..<totalFrames {
            leftPtr[i] = 0
            rightPtr[i] = 0
        }

        // Equal-power stereo law: pan in [-1, +1] -> angle in [0, pi/2]
        let angle = (pan + 1.0) * 0.25 * Float.pi
        let gainL = cos(angle) * gain
        let gainR = sin(angle) * gain

        mono.withUnsafeBufferPointer { src in
            for i in 0..<resampledLen {
                let pos = Float(i) * rate
                let idx = Int(pos)
                let frac = pos - Float(idx)
                let s0 = src[idx]
                let s1 = (idx + 1 < srcCount) ? src[idx + 1] : 0
                let sample = s0 + (s1 - s0) * frac

                leftPtr[i + leftDelay] = sample * gainL
                rightPtr[i + rightDelay] = sample * gainR
            }
        }

        return buffer
    }
}
