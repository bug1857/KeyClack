import Foundation

/// A single canonical 48 kHz mono floating-point audio clip ready for zero-latency playback.
struct SampleClip {
    let samples: [Float]

    var frameCount: Int { samples.count }
}

/// Complete bank of pre-rendered downstroke & upstroke sound variations for one switch profile.
struct SynthesizedSwitchBank {
    let downClips: [KeyCategory: [SampleClip]]
    let upClips: [KeyCategory: [SampleClip]]
}

/// Physical-modeling mechanical keyboard synthesizer.
/// Generates realistic, multi-layered 48 kHz acoustic impulses (finger tap, tactile/click/dome
/// actuation, keycap Helmholtz cavity resonance, case/desk body thock, stabilizer micro-doublet,
/// and separate top-out return upstrokes) with round-robin organic variations.
final class SwitchSynthesizer {
    static let sampleRate: Float = 48_000.0
    static let variationsPerCategory = 6

    private struct XorShift64 {
        var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        }

        mutating func nextUInt64() -> UInt64 {
            var x = state
            x ^= x << 13
            x ^= x >> 7
            x ^= x << 17
            state = x
            return x
        }

        /// Uniform random Float in [-1, 1].
        mutating func nextSignedFloat() -> Float {
            let u = Float(nextUInt64() >> 40) / Float(1 << 24)
            return u * 2.0 - 1.0
        }

        /// Uniform random Float in [0, 1].
        mutating func nextUnitFloat() -> Float {
            Float(nextUInt64() >> 40) / Float(1 << 24)
        }
    }

    /// Standard RBJ Audio EQ Cookbook second-order biquad filter.
    private struct Biquad {
        var b0: Float = 1
        var b1: Float = 0
        var b2: Float = 0
        var a1: Float = 0
        var a2: Float = 0
        var x1: Float = 0
        var x2: Float = 0
        var y1: Float = 0
        var y2: Float = 0

        static func bandpass(freq: Float, q: Float, sampleRate: Float) -> Biquad {
            let clampedFreq = max(30.0, min(freq, sampleRate * 0.46))
            let clampedQ = max(0.35, q)
            let w0 = 2.0 * Float.pi * clampedFreq / sampleRate
            let alpha = sin(w0) / (2.0 * clampedQ)
            let a0 = 1.0 + alpha
            var f = Biquad()
            // Constant 0 dB peak gain bandpass (RBJ Audio EQ Cookbook)
            f.b0 = alpha / a0
            f.b1 = 0
            f.b2 = -alpha / a0
            f.a1 = (-2.0 * cos(w0)) / a0
            f.a2 = (1.0 - alpha) / a0
            return f
        }

        static func lowpass(freq: Float, q: Float, sampleRate: Float) -> Biquad {
            let clampedFreq = max(40.0, min(freq, sampleRate * 0.46))
            let w0 = 2.0 * Float.pi * clampedFreq / sampleRate
            let cosW0 = cos(w0)
            let alpha = sin(w0) / (2.0 * max(0.4, q))
            let a0 = 1.0 + alpha
            var f = Biquad()
            f.b0 = ((1.0 - cosW0) * 0.5) / a0
            f.b1 = (1.0 - cosW0) / a0
            f.b2 = ((1.0 - cosW0) * 0.5) / a0
            f.a1 = (-2.0 * cosW0) / a0
            f.a2 = (1.0 - alpha) / a0
            return f
        }

        static func highpass(freq: Float, q: Float, sampleRate: Float) -> Biquad {
            let clampedFreq = max(20.0, min(freq, sampleRate * 0.45))
            let w0 = 2.0 * Float.pi * clampedFreq / sampleRate
            let cosW0 = cos(w0)
            let alpha = sin(w0) / (2.0 * max(0.4, q))
            let a0 = 1.0 + alpha
            var f = Biquad()
            f.b0 = ((1.0 + cosW0) * 0.5) / a0
            f.b1 = -(1.0 + cosW0) / a0
            f.b2 = ((1.0 + cosW0) * 0.5) / a0
            f.a1 = (-2.0 * cosW0) / a0
            f.a2 = (1.0 - alpha) / a0
            return f
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            return y
        }
    }

    /// Synthesizes a complete round-robin bank for a built-in switch profile.
    static func synthesizeBank(for builtIn: BuiltInSwitch) -> SynthesizedSwitchBank {
        let spec = builtIn.spec
        var downClips: [KeyCategory: [SampleClip]] = [:]
        var upClips: [KeyCategory: [SampleClip]] = [:]

        var baseSeed: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in builtIn.rawValue.utf8 {
            baseSeed ^= UInt64(byte)
            baseSeed &*= 0x0000_0100_0000_01B3
        }

        for category in KeyCategory.allCases {
            var downs: [SampleClip] = []
            var ups: [SampleClip] = []
            downs.reserveCapacity(variationsPerCategory)
            ups.reserveCapacity(variationsPerCategory)

            for v in 0..<variationsPerCategory {
                let downSeed = baseSeed &+ UInt64(category.rawValue * 97 + v * 13 + 1)
                let upSeed = baseSeed &+ UInt64(category.rawValue * 193 + v * 29 + 777)
                downs.append(renderDownstroke(spec: spec, category: category, seed: downSeed))
                ups.append(renderUpstroke(spec: spec, category: category, seed: upSeed))
            }

            downClips[category] = downs
            upClips[category] = ups
        }

        return SynthesizedSwitchBank(downClips: downClips, upClips: upClips)
    }

    private static func renderDownstroke(
        spec: AcousticSpec,
        category: KeyCategory,
        seed: UInt64
    ) -> SampleClip {
        var rng = XorShift64(seed: seed)
        let sr = sampleRate
        let durationSec: Float = 0.115
        let count = Int(sr * durationSec)
        var out = [Float](repeating: 0, count: count)

        // Organic per-variation modal micro-detune so every round-robin clip has its own voice
        let varPitch = 1.0 + rng.nextSignedFloat() * 0.022
        let pitchMult = category.pitchMultiplier * varPitch
        let decayMult = category.decayMultiplier * (1.0 + rng.nextSignedFloat() * 0.05)

        // 1. Subtle finger-on-keycap touch (t = 0 ms)
        addResonantBurst(
            into: &out,
            delayMs: 0.0,
            exciteMs: 2.2,
            decayMs: 6.5,
            freq: 460 * pitchMult,
            q: 1.1,
            gain: 0.13,
            impulseSpike: 0.0,
            rng: &rng
        )

        // 2. Mid-travel actuation event (tactile bump / click jacket / click bar / rubber dome)
        if spec.actuationGain > 0.01 {
            let actJitter = rng.nextSignedFloat() * 0.35
            let actDelay = max(0.8, spec.actuationDelayMs + actJitter)
            addResonantBurst(
                into: &out,
                delayMs: actDelay,
                exciteMs: 1.6,
                decayMs: spec.actuationDecayMs,
                freq: spec.actuationFreq * (0.92 + 0.08 * pitchMult),
                q: spec.actuationQ,
                gain: spec.actuationGain * 0.85,
                impulseSpike: spec.actuationGain > 0.7 ? 0.55 : 0.22,
                rng: &rng
            )
            // Secondary high click snap for clicky/buckling switches
            if spec.actuationGain > 0.75 {
                addResonantBurst(
                    into: &out,
                    delayMs: actDelay + 0.55,
                    exciteMs: 0.9,
                    decayMs: 2.4,
                    freq: min(spec.actuationFreq * 1.42, 7400),
                    q: 3.0,
                    gain: spec.actuationGain * 0.48,
                    impulseSpike: 0.45,
                    rng: &rng
                )
            }
        }

        // 3. Main bottom-out impact: 3 parallel acoustic modal resonators
        let bottomDelay = spec.bottomOutDelayMs + rng.nextSignedFloat() * 0.45
        addBottomOutImpact(
            into: &out,
            delayMs: bottomDelay,
            spec: spec,
            pitchMult: pitchMult,
            decayMult: decayMult,
            amplitudeScale: 1.0,
            rng: &rng
        )

        // 4. Stabilized large keys (Space, Enter, Backspace, Shift): micro-asynchronous doublet + hollow bar resonance
        if category.stabilizerOffsetMs > 0 {
            let stabDelay = bottomDelay + category.stabilizerOffsetMs + rng.nextSignedFloat() * 0.25
            addBottomOutImpact(
                into: &out,
                delayMs: stabDelay,
                spec: spec,
                pitchMult: pitchMult * 0.94,
                decayMult: decayMult * 1.06,
                amplitudeScale: category == .space ? 0.46 : 0.34,
                rng: &rng
            )
            if category == .space {
                // Hollow 6.25u PBT spacebar resonant cavity mode
                addResonantBurst(
                    into: &out,
                    delayMs: bottomDelay + 0.6,
                    exciteMs: 3.2,
                    decayMs: spec.bodyDecayMs * 1.35,
                    freq: max(115, spec.bodyFreq * 1.55 * pitchMult),
                    q: 2.6,
                    gain: spec.bodyGain * 0.42,
                    impulseSpike: 0.12,
                    rng: &rng
                )
            }
        }

        // 5. Metallic buckling-spring ping (IBM Model M)
        if spec.springPingGain > 0.001 && spec.springPingFreq1 > 0 {
            addSpringPing(
                into: &out,
                delayMs: spec.actuationDelayMs + 0.4,
                freq1: spec.springPingFreq1 * (1.0 + rng.nextSignedFloat() * 0.018),
                freq2: spec.springPingFreq2 * (1.0 + rng.nextSignedFloat() * 0.022),
                decayMs: spec.springPingDecayMs,
                gain: spec.springPingGain,
                rng: &rng
            )
        }

        return masterClip(
            out,
            brightnessHz: spec.brightnessHz,
            drive: spec.drive,
            targetPeak: min(0.94, 0.80 * category.gainMultiplier)
        )
    }

    private static func renderUpstroke(
        spec: AcousticSpec,
        category: KeyCategory,
        seed: UInt64
    ) -> SampleClip {
        var rng = XorShift64(seed: seed)
        let sr = sampleRate
        let durationSec: Float = 0.078
        let count = Int(sr * durationSec)
        var out = [Float](repeating: 0, count: count)

        let varPitch = 1.0 + rng.nextSignedFloat() * 0.026
        let pitchMult = category.pitchMultiplier * spec.upstrokePitchMult * varPitch
        let decayMult = category.decayMultiplier * 0.68

        // Top-housing return impact: lighter body, hollower cavity "tok", crisp plastic top-out
        addResonantBurst(
            into: &out,
            delayMs: 0.4,
            exciteMs: 1.8,
            decayMs: spec.bodyDecayMs * 0.55 * decayMult,
            freq: spec.bodyFreq * pitchMult,
            q: spec.bodyQ * 0.85,
            gain: spec.bodyGain * 0.30,
            impulseSpike: 0.12,
            rng: &rng
        )

        addResonantBurst(
            into: &out,
            delayMs: 0.6,
            exciteMs: 2.0,
            decayMs: spec.cavityDecayMs * 0.72 * decayMult,
            freq: spec.cavityFreq * pitchMult,
            q: spec.cavityQ * 0.92,
            gain: spec.cavityGain * 0.78,
            impulseSpike: 0.22,
            rng: &rng
        )

        addResonantBurst(
            into: &out,
            delayMs: 0.8,
            exciteMs: 1.4,
            decayMs: spec.clackDecayMs * 0.78,
            freq: min(spec.clackFreq * (0.75 + 0.25 * pitchMult), 6800),
            q: spec.clackQ,
            gain: max(0.32, spec.clackGain * 0.90),
            impulseSpike: 0.35,
            rng: &rng
        )

        // Return click bar / click jacket reset (e.g. Box Jade's signature upstroke snap)
        if spec.upstrokeClickGain > 0.02 {
            addResonantBurst(
                into: &out,
                delayMs: 1.7 + rng.nextSignedFloat() * 0.2,
                exciteMs: 1.1,
                decayMs: 3.2,
                freq: min(spec.actuationFreq * 1.12, 7200),
                q: spec.actuationQ,
                gain: spec.upstrokeClickGain,
                impulseSpike: 0.48,
                rng: &rng
            )
        }

        // Stabilized return micro-doublet
        if category.stabilizerOffsetMs > 0 {
            addResonantBurst(
                into: &out,
                delayMs: 0.6 + category.stabilizerOffsetMs * 0.65,
                exciteMs: 1.8,
                decayMs: spec.cavityDecayMs * 0.75 * decayMult,
                freq: spec.cavityFreq * pitchMult * 0.92,
                q: spec.cavityQ * 0.85,
                gain: spec.cavityGain * 0.36,
                impulseSpike: 0.14,
                rng: &rng
            )
        }

        let targetPeak = min(0.75, 0.78 * spec.upstrokeGain * category.gainMultiplier)
        return masterClip(
            out,
            brightnessHz: min(spec.brightnessHz * 1.12, 9500),
            drive: max(1.15, spec.drive * 0.88),
            targetPeak: targetPeak
        )
    }

    private static func addBottomOutImpact(
        into out: inout [Float],
        delayMs: Float,
        spec: AcousticSpec,
        pitchMult: Float,
        decayMult: Float,
        amplitudeScale: Float,
        rng: inout XorShift64
    ) {
        // Mode 1: Case / desk low-end thock
        addResonantBurst(
            into: &out,
            delayMs: delayMs,
            exciteMs: 3.0,
            decayMs: spec.bodyDecayMs * decayMult,
            freq: spec.bodyFreq * pitchMult,
            q: spec.bodyQ,
            gain: spec.bodyGain * amplitudeScale,
            impulseSpike: 0.30,
            rng: &rng
        )

        // Mode 2: Keycap cavity / PE-foam marbly resonance
        addResonantBurst(
            into: &out,
            delayMs: delayMs + 0.25,
            exciteMs: 2.3,
            decayMs: spec.cavityDecayMs * decayMult,
            freq: spec.cavityFreq * (0.45 + 0.55 * pitchMult),
            q: spec.cavityQ,
            gain: spec.cavityGain * amplitudeScale,
            impulseSpike: 0.28,
            rng: &rng
        )

        // Mode 3: Stem-on-housing crisp clack
        addResonantBurst(
            into: &out,
            delayMs: delayMs + 0.1,
            exciteMs: 1.5,
            decayMs: spec.clackDecayMs,
            freq: spec.clackFreq * (0.72 + 0.28 * pitchMult),
            q: spec.clackQ,
            gain: spec.clackGain * amplitudeScale,
            impulseSpike: 0.42,
            rng: &rng
        )
    }

    /// Excites a resonant bandpass modal filter with a short stochastic impact impulse + exponential decay.
    private static func addResonantBurst(
        into out: inout [Float],
        delayMs: Float,
        exciteMs: Float,
        decayMs: Float,
        freq: Float,
        q: Float,
        gain: Float,
        impulseSpike: Float,
        rng: inout XorShift64
    ) {
        let sr = sampleRate
        let startIdx = max(0, Int((delayMs / 1000.0) * sr))
        guard startIdx < out.count else { return }

        let exciteSamples = max(8, Int((exciteMs / 1000.0) * sr))
        let decaySamples = max(24, Int((decayMs / 1000.0) * sr))
        let totalSamples = min(out.count - startIdx, decaySamples * 5 + exciteSamples)

        var bp = Biquad.bandpass(freq: freq, q: q, sampleRate: sr)
        // Bandwidth-energy equalization so deep case thock and crisp high clicks balance naturally
        let eqGain = pow(650.0 / max(80.0, freq), 0.25)

        for i in 0..<totalSamples {
            var exc: Float = 0
            if i < exciteSamples {
                // Fast half-sine / exponential noise impulse simulating solid surface collision
                let tNorm = Float(i) / Float(exciteSamples)
                let attackEnv = sin(min(1.0, tNorm * 3.5) * Float.pi * 0.5)
                let exciteDecay = exp(-tNorm * 3.8)
                exc = rng.nextSignedFloat() * attackEnv * exciteDecay
                if i == 1 {
                    exc += impulseSpike
                } else if i == 2 {
                    exc -= impulseSpike * 0.45
                }
            }
            let filtered = bp.process(exc)
            // Controlled acoustic damping envelope so modes stay punchy and never ring artificially
            let env = exp(-Float(i) / Float(decaySamples))
            out[startIdx + i] += filtered * env * gain * eqGain
        }
    }

    /// Adds authentic subtle damped metallic spring resonance (IBM Model M).
    private static func addSpringPing(
        into out: inout [Float],
        delayMs: Float,
        freq1: Float,
        freq2: Float,
        decayMs: Float,
        gain: Float,
        rng: inout XorShift64
    ) {
        let sr = sampleRate
        let startIdx = max(0, Int((delayMs / 1000.0) * sr))
        guard startIdx < out.count else { return }

        let decaySamples = max(48, Int((decayMs / 1000.0) * sr))
        let phase1Start = rng.nextUnitFloat() * 2.0 * Float.pi
        let phase2Start = rng.nextUnitFloat() * 2.0 * Float.pi
        let w1 = 2.0 * Float.pi * freq1 / sr
        let w2 = 2.0 * Float.pi * freq2 / sr
        let total = min(out.count - startIdx, decaySamples * 5)

        for i in 0..<total {
            let fi = Float(i)
            let attack = min(1.0, fi / 24.0)
            let env1 = exp(-fi / Float(decaySamples))
            let env2 = exp(-fi / (Float(decaySamples) * 0.55))
            let s1 = sin(phase1Start + w1 * fi) * env1
            let s2 = sin(phase2Start + w2 * fi) * env2 * 0.45
            out[startIdx + i] += (s1 + s2) * attack * gain
        }
    }

    /// Applies subtle early desk-surface reflection, gentle brightness shaping, DC-blocking HPF,
    /// warm tanh punch, normalization, and click-free fades.
    private static func masterClip(
        _ input: [Float],
        brightnessHz: Float,
        drive: Float,
        targetPeak: Float
    ) -> SampleClip {
        var samples = input
        let sr = sampleRate

        // Subtle early desk-surface reflection (~4.2 ms, warm -16 dB) gives physical studio depth
        let reflectDelay = Int(0.0042 * sr)
        if samples.count > reflectDelay {
            var reflectLP = Biquad.lowpass(freq: min(brightnessHz * 0.6, 2200), q: 0.707, sampleRate: sr)
            for i in reflectDelay..<samples.count {
                samples[i] += reflectLP.process(input[i - reflectDelay]) * 0.16
            }
        }

        var hpf = Biquad.highpass(freq: 48.0, q: 0.707, sampleRate: sr)
        var lpf = Biquad.lowpass(freq: brightnessHz, q: 0.72, sampleRate: sr)

        var maxAbs: Float = 0.00001
        for i in 0..<samples.count {
            let s = lpf.process(hpf.process(samples[i]))
            samples[i] = s
            let a = abs(s)
            if a > maxAbs { maxAbs = a }
        }

        // Normalize before warm soft-clip saturation so drive behaves identically across profiles
        let preNorm = 1.0 / maxAbs
        let tanhDrive = tanh(drive)
        var postPeak: Float = 0.00001
        for i in 0..<samples.count {
            let shaped = tanh(samples[i] * preNorm * drive) / tanhDrive
            samples[i] = shaped
            let a = abs(shaped)
            if a > postPeak { postPeak = a }
        }

        let finalScale = targetPeak / postPeak
        let fadeInLen = min(16, samples.count)
        let fadeOutLen = min(360, samples.count)

        for i in 0..<samples.count {
            var s = samples[i] * finalScale
            if i < fadeInLen {
                s *= Float(i) / Float(fadeInLen)
            }
            let distFromEnd = samples.count - 1 - i
            if distFromEnd < fadeOutLen {
                s *= Float(distFromEnd) / Float(fadeOutLen)
            }
            samples[i] = s
        }

        return SampleClip(samples: samples)
    }
}
