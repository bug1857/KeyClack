import Foundation

/// Acoustic category of a mechanical keyboard switch.
enum SwitchCategory: String, Codable, CaseIterable {
    case tactile = "Tactile"
    case linear = "Linear"
    case clicky = "Clicky"
    case capacitive = "Topre"
    case buckling = "Buckling"
    case custom = "Imported"
}

/// Physical-modeling acoustic parameters for synthesizing realistic mechanical switch sounds.
/// Every parameter maps directly to a physical layer of a mechanical keystroke:
/// finger touch -> actuation event -> bottom-out modal resonance (case + keycap cavity + stem impact)
/// and a separate top-out return upstroke.
struct AcousticSpec: Hashable {
    // Mode 1: Case / Plate / Desk low-frequency body thump ("thock")
    let bodyFreq: Float
    let bodyQ: Float
    let bodyDecayMs: Float
    let bodyGain: Float

    // Mode 2: Keycap hollow cavity & PE-foam "marbly" resonance
    let cavityFreq: Float
    let cavityQ: Float
    let cavityDecayMs: Float
    let cavityGain: Float

    // Mode 3: Stem-on-housing crisp impact transient ("clack")
    let clackFreq: Float
    let clackQ: Float
    let clackDecayMs: Float
    let clackGain: Float

    // Mid-travel actuation event (tactile bump, click jacket, click bar, rubber dome)
    let actuationDelayMs: Float
    let actuationFreq: Float
    let actuationQ: Float
    let actuationDecayMs: Float
    let actuationGain: Float

    // Timing from initial touch to bottom-out impact
    let bottomOutDelayMs: Float

    // Optional damped metallic spring ping (e.g., IBM Model M buckling spring)
    let springPingFreq1: Float
    let springPingFreq2: Float
    let springPingGain: Float
    let springPingDecayMs: Float

    // Key-up (top-out housing return)
    let upstrokeGain: Float
    let upstrokePitchMult: Float
    let upstrokeClickGain: Float

    // Mastering warmth & high-frequency ceiling
    let drive: Float
    let brightnessHz: Float
}

/// Six built-in, acoustically modeled mechanical keyboard switch profiles.
enum BuiltInSwitch: String, Codable, CaseIterable, Identifiable, Hashable {
    case holyPanda = "holy_panda"
    case oilKing = "oil_king"
    case cherryMXBlue = "cherry_mx_blue"
    case boxJade = "box_jade"
    case topre45g = "topre_45g"
    case modelM = "model_m"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .holyPanda: return "Holy Panda"
        case .oilKing: return "Oil King"
        case .cherryMXBlue: return "Cherry MX Blue"
        case .boxJade: return "Kailh Box Jade"
        case .topre45g: return "Topre 45g"
        case .modelM: return "IBM Model M"
        }
    }

    var subtitle: String {
        switch self {
        case .holyPanda: return "Rounded tactile · deep PBT thock"
        case .oilKing: return "Lubed linear · creamy marbly pop"
        case .cherryMXBlue: return "Click jacket · crisp bright clack"
        case .boxJade: return "Thick clickbar · dual snap click"
        case .topre45g: return "Electro-capacitive · velvety thock"
        case .modelM: return "Buckling spring · metallic ping"
        }
    }

    var category: SwitchCategory {
        switch self {
        case .holyPanda: return .tactile
        case .oilKing: return .linear
        case .cherryMXBlue: return .clicky
        case .boxJade: return .clicky
        case .topre45g: return .capacitive
        case .modelM: return .buckling
        }
    }

    /// Stem accent color as (R, G, B) in 0...1 for the menu bar UI.
    var accentRGB: (Double, Double, Double) {
        switch self {
        case .holyPanda: return (0.95, 0.48, 0.38)    // Salmon / Halo True stem
        case .oilKing: return (0.35, 0.68, 0.96)      // Midnight oil blue
        case .cherryMXBlue: return (0.20, 0.62, 0.98) // Classic Cherry blue
        case .boxJade: return (0.22, 0.78, 0.56)      // Jade green
        case .topre45g: return (0.64, 0.54, 0.92)     // Realforce plum/violet
        case .modelM: return (0.86, 0.68, 0.32)       // Vintage beige/amber
        }
    }

    var spec: AcousticSpec {
        switch self {
        case .holyPanda:
            return AcousticSpec(
                bodyFreq: 195, bodyQ: 1.75, bodyDecayMs: 36, bodyGain: 0.95,
                cavityFreq: 860, cavityQ: 2.8, cavityDecayMs: 21, cavityGain: 0.98,
                clackFreq: 2350, clackQ: 1.9, clackDecayMs: 10, clackGain: 0.62,
                actuationDelayMs: 2.2, actuationFreq: 1650, actuationQ: 2.2, actuationDecayMs: 5.5, actuationGain: 0.52,
                bottomOutDelayMs: 6.2,
                springPingFreq1: 0, springPingFreq2: 0, springPingGain: 0, springPingDecayMs: 0,
                upstrokeGain: 0.48, upstrokePitchMult: 1.32, upstrokeClickGain: 0.06,
                drive: 1.55, brightnessHz: 5400
            )

        case .oilKing:
            return AcousticSpec(
                bodyFreq: 162, bodyQ: 1.95, bodyDecayMs: 42, bodyGain: 1.08,
                cavityFreq: 720, cavityQ: 3.4, cavityDecayMs: 24, cavityGain: 1.22,
                clackFreq: 1820, clackQ: 1.7, clackDecayMs: 9.5, clackGain: 0.42,
                actuationDelayMs: 1.8, actuationFreq: 950, actuationQ: 1.2, actuationDecayMs: 4.5, actuationGain: 0.10,
                bottomOutDelayMs: 5.0,
                springPingFreq1: 0, springPingFreq2: 0, springPingGain: 0, springPingDecayMs: 0,
                upstrokeGain: 0.44, upstrokePitchMult: 1.28, upstrokeClickGain: 0.0,
                drive: 1.65, brightnessHz: 4200
            )

        case .cherryMXBlue:
            return AcousticSpec(
                bodyFreq: 265, bodyQ: 1.5, bodyDecayMs: 26, bodyGain: 0.72,
                cavityFreq: 1220, cavityQ: 2.5, cavityDecayMs: 15, cavityGain: 0.82,
                clackFreq: 3150, clackQ: 2.4, clackDecayMs: 9.0, clackGain: 0.76,
                actuationDelayMs: 2.0, actuationFreq: 4650, actuationQ: 3.6, actuationDecayMs: 3.6, actuationGain: 0.95,
                bottomOutDelayMs: 7.4,
                springPingFreq1: 0, springPingFreq2: 0, springPingGain: 0, springPingDecayMs: 0,
                upstrokeGain: 0.50, upstrokePitchMult: 1.40, upstrokeClickGain: 0.24,
                drive: 1.40, brightnessHz: 8600
            )

        case .boxJade:
            return AcousticSpec(
                bodyFreq: 215, bodyQ: 1.8, bodyDecayMs: 30, bodyGain: 0.88,
                cavityFreq: 1020, cavityQ: 2.9, cavityDecayMs: 18, cavityGain: 0.94,
                clackFreq: 2850, clackQ: 2.3, clackDecayMs: 10, clackGain: 0.72,
                actuationDelayMs: 2.1, actuationFreq: 3900, actuationQ: 3.2, actuationDecayMs: 4.4, actuationGain: 1.15,
                bottomOutDelayMs: 7.0,
                springPingFreq1: 0, springPingFreq2: 0, springPingGain: 0, springPingDecayMs: 0,
                upstrokeGain: 0.56, upstrokePitchMult: 1.36, upstrokeClickGain: 0.68,
                drive: 1.60, brightnessHz: 8200
            )

        case .topre45g:
            return AcousticSpec(
                bodyFreq: 148, bodyQ: 1.65, bodyDecayMs: 44, bodyGain: 1.15,
                cavityFreq: 590, cavityQ: 2.2, cavityDecayMs: 25, cavityGain: 1.05,
                clackFreq: 1420, clackQ: 1.4, clackDecayMs: 11, clackGain: 0.32,
                actuationDelayMs: 2.5, actuationFreq: 680, actuationQ: 1.5, actuationDecayMs: 7.5, actuationGain: 0.46,
                bottomOutDelayMs: 6.5,
                springPingFreq1: 0, springPingFreq2: 0, springPingGain: 0, springPingDecayMs: 0,
                upstrokeGain: 0.58, upstrokePitchMult: 1.30, upstrokeClickGain: 0.0,
                drive: 1.45, brightnessHz: 3300
            )

        case .modelM:
            return AcousticSpec(
                bodyFreq: 240, bodyQ: 1.6, bodyDecayMs: 32, bodyGain: 0.84,
                cavityFreq: 1140, cavityQ: 2.7, cavityDecayMs: 17, cavityGain: 0.88,
                clackFreq: 2980, clackQ: 2.2, clackDecayMs: 9.5, clackGain: 0.74,
                actuationDelayMs: 2.4, actuationFreq: 4200, actuationQ: 3.1, actuationDecayMs: 4.2, actuationGain: 1.05,
                bottomOutDelayMs: 6.8,
                springPingFreq1: 1860, springPingFreq2: 4180, springPingGain: 0.14, springPingDecayMs: 36,
                upstrokeGain: 0.46, upstrokePitchMult: 1.38, upstrokeClickGain: 0.22,
                drive: 1.50, brightnessHz: 8000
            )
        }
    }
}

/// Metadata for a user-imported Mechvibes V1/V2 or custom WAV/MP3/FLAC sound pack.
struct ImportedSoundPack: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let author: String
    let formatDescription: String
    let hasKeyUpSounds: Bool
    let keyCount: Int
    let importedAt: Date
}

/// Identifies the active sound source: either a built-in acoustic switch or an imported pack.
enum ActiveProfileSelection: Codable, Hashable {
    case builtIn(BuiltInSwitch)
    case imported(String)
}
