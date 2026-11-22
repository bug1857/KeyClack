import XCTest
import AVFoundation
@testable import KeyClackCore

final class KeyClackTests: XCTestCase {

    // MARK: - 1. SwitchSynthesizer Acoustic Integrity

    func testAllSixSwitchesSynthesizeCleanly() {
        for sw in BuiltInSwitch.allCases {
            let bank = SwitchSynthesizer.synthesizeBank(for: sw)

            for category in KeyCategory.allCases {
                let downs = bank.downClips[category] ?? []
                let ups = bank.upClips[category] ?? []

                XCTAssertEqual(downs.count, SwitchSynthesizer.variationsPerCategory, "\(sw.displayName) down count for \(category)")
                XCTAssertEqual(ups.count, SwitchSynthesizer.variationsPerCategory, "\(sw.displayName) up count for \(category)")

                for clip in downs {
                    XCTAssertGreaterThan(clip.frameCount, 4000, "\(sw.displayName) down clip length")
                    let peak = verifyClipHealth(clip, label: "\(sw.displayName) \(category) down")
                    XCTAssertGreaterThan(peak, 0.50, "\(sw.displayName) down peak should be audible")
                    XCTAssertLessThanOrEqual(peak, 0.96, "\(sw.displayName) down peak should never clip")
                }

                for clip in ups {
                    XCTAssertGreaterThan(clip.frameCount, 2500, "\(sw.displayName) up clip length")
                    let peak = verifyClipHealth(clip, label: "\(sw.displayName) \(category) up")
                    XCTAssertGreaterThan(peak, 0.20, "\(sw.displayName) up peak should be audible")
                    XCTAssertLessThanOrEqual(peak, 0.80, "\(sw.displayName) up peak should stay softer than down")
                }
            }
        }
    }

    func testSwitchSynthesisIsDeterministicAcrossCalls() {
        let bankA = SwitchSynthesizer.synthesizeBank(for: .holyPanda)
        let bankB = SwitchSynthesizer.synthesizeBank(for: .holyPanda)
        XCTAssertEqual(bankA.downClips[.alpha]?.first?.samples, bankB.downClips[.alpha]?.first?.samples)
        XCTAssertEqual(bankA.upClips[.space]?.first?.samples, bankB.upClips[.space]?.first?.samples)
    }

    func testClickyVsThockyAcousticDifferentiation() {
        let mxBlue = SwitchSynthesizer.synthesizeBank(for: .cherryMXBlue).downClips[.alpha]![0].samples
        let oilKing = SwitchSynthesizer.synthesizeBank(for: .oilKing).downClips[.alpha]![0].samples

        // Approximate high-frequency energy using first-difference energy (high-pass derivative)
        let blueBrightness = highFreqRatio(mxBlue)
        let oilKingBrightness = highFreqRatio(oilKing)

        XCTAssertGreaterThan(
            blueBrightness,
            oilKingBrightness * 1.5,
            "Cherry MX Blue (\(blueBrightness)) should be significantly brighter than Oil King (\(oilKingBrightness))"
        )
    }

    // MARK: - 2. KeyLayoutMap Spatial Panning & Keycode Mappings

    func testSpatialPanningAndStabilizerCategories() {
        XCTAssertLessThan(KeyLayoutMap.info(for: 12).pan, -0.5, "Q should pan left")
        XCTAssertLessThan(KeyLayoutMap.info(for: 0).pan, -0.5, "A should pan left")
        XCTAssertEqual(KeyLayoutMap.info(for: 49).pan, 0.0, accuracy: 0.001, "Space should be centered")
        XCTAssertGreaterThan(KeyLayoutMap.info(for: 35).pan, 0.4, "P should pan right")
        XCTAssertGreaterThan(KeyLayoutMap.info(for: 51).pan, 0.8, "Backspace should pan far right")

        XCTAssertEqual(KeyLayoutMap.info(for: 49).category, .space)
        XCTAssertEqual(KeyLayoutMap.info(for: 36).category, .enter)
        XCTAssertEqual(KeyLayoutMap.info(for: 51).category, .backspace)
        XCTAssertEqual(KeyLayoutMap.info(for: 56).category, .shift)
        XCTAssertEqual(KeyLayoutMap.info(for: 60).category, .shift)
        XCTAssertEqual(KeyLayoutMap.info(for: 55).category, .modifier)

        // Mechvibes V1 & V2 keycode mappings
        XCTAssertEqual(KeyLayoutMap.macKeyCode(fromV1Code: 30), 0, "V1 30 -> KeyA (0)")
        XCTAssertEqual(KeyLayoutMap.macKeyCode(fromV1Code: 57), 49, "V1 57 -> Space (49)")
        XCTAssertEqual(KeyLayoutMap.macKeyCode(fromV1Code: 28), 36, "V1 28 -> Enter (36)")
        XCTAssertEqual(KeyLayoutMap.macKeyCode(fromW3CCode: "KeyA"), 0)
        XCTAssertEqual(KeyLayoutMap.macKeyCode(fromW3CCode: "Space"), 49)
        XCTAssertEqual(KeyLayoutMap.macKeyCode(fromW3CCode: "Enter"), 36)
        XCTAssertEqual(KeyLayoutMap.macKeyCode(fromW3CCode: "Backspace"), 51)
    }

    // MARK: - 3. SoundPackImporter (Mechvibes V1, Mechvibes V2 Down+Up, ZIP, Plain WAV Folder)

    func testImportMechvibesV1SinglePack() throws {
        let tmpDir = try makeTempDir("v1-single")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try writeTestWav(to: tmpDir.appendingPathComponent("sound.wav"), sampleRate: 44_100, durationSec: 1.0, freq: 650)
        let config = """
        {
          "name": "Test V1 Single",
          "author": "UnitTest",
          "key_define_type": "single",
          "sound": "sound.wav",
          "defines": {
            "30": [50, 120],
            "57": [250, 150],
            "28": [450, 130]
          }
        }
        """
        try config.write(to: tmpDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        let pack = try SoundPackImporter.importPack(from: tmpDir)
        defer { SoundPackImporter.deletePack(id: pack.metadata.id) }

        XCTAssertEqual(pack.metadata.name, "Test V1 Single")
        XCTAssertFalse(pack.metadata.hasKeyUpSounds)
        XCTAssertNotNil(pack.clip(for: 0, category: .alpha, isDown: true, cycleIndex: 0))
        XCTAssertNotNil(pack.clip(for: 49, category: .space, isDown: true, cycleIndex: 0))
        XCTAssertNotNil(pack.clip(for: 36, category: .enter, isDown: true, cycleIndex: 0))
        // Unmapped key should gracefully fall back
        XCTAssertNotNil(pack.clip(for: 12, category: .alpha, isDown: true, cycleIndex: 1))
    }

    func testImportMechvibesV2SingleWithDownAndUpSlicesAndZip() throws {
        let tmpDir = try makeTempDir("v2-single")
        let zipURL = tmpDir.appendingPathComponent("TestV2Pack.zip")
        let packFolder = tmpDir.appendingPathComponent("pack-root", isDirectory: true)
        try FileManager.default.createDirectory(at: packFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try writeTestWav(to: packFolder.appendingPathComponent("switches.wav"), sampleRate: 48_000, durationSec: 1.0, freq: 880)
        let config = """
        {
          "id": "test-v2-zip",
          "name": "Test V2 Dual Stroke",
          "author": "UnitTest",
          "config_version": "2",
          "definition_method": "single",
          "audio_file": "switches.wav",
          "definitions": {
            "KeyA": { "timing": [[40, 140], [180, 260]] },
            "Space": { "timing": [[300, 440], [480, 580]] }
          }
        }
        """
        try config.write(to: packFolder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        // Create a real ZIP archive using macOS /usr/bin/zip
        let zipProc = Process()
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProc.currentDirectoryURL = tmpDir
        zipProc.arguments = ["-r", "-q", zipURL.path, "pack-root"]
        try zipProc.run()
        zipProc.waitUntilExit()
        XCTAssertEqual(zipProc.terminationStatus, 0)

        let pack = try SoundPackImporter.importPack(from: zipURL)
        defer { SoundPackImporter.deletePack(id: pack.metadata.id) }

        XCTAssertEqual(pack.metadata.name, "Test V2 Dual Stroke")
        XCTAssertTrue(pack.metadata.hasKeyUpSounds)
        XCTAssertNotNil(pack.clip(for: 0, category: .alpha, isDown: true, cycleIndex: 0))
        XCTAssertNotNil(pack.clip(for: 0, category: .alpha, isDown: false, cycleIndex: 0))
        XCTAssertNotNil(pack.clip(for: 49, category: .space, isDown: true, cycleIndex: 0))
        XCTAssertNotNil(pack.clip(for: 49, category: .space, isDown: false, cycleIndex: 0))

        // Verify reloading persisted pack from Application Support works
        let reloaded = try SoundPackImporter.loadSavedPack(id: pack.metadata.id)
        XCTAssertEqual(reloaded.metadata.name, "Test V2 Dual Stroke")
        XCTAssertTrue(reloaded.metadata.hasKeyUpSounds)
    }

    func testImportPlainWavFolderAutoCategorizesKeys() throws {
        let tmpDir = try makeTempDir("plain-wav")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try writeTestWav(to: tmpDir.appendingPathComponent("alpha_down.wav"), sampleRate: 48_000, durationSec: 0.12, freq: 720)
        try writeTestWav(to: tmpDir.appendingPathComponent("alpha_up.wav"), sampleRate: 48_000, durationSec: 0.08, freq: 1100)
        try writeTestWav(to: tmpDir.appendingPathComponent("space_down.wav"), sampleRate: 48_000, durationSec: 0.14, freq: 300)
        try writeTestWav(to: tmpDir.appendingPathComponent("enter.wav"), sampleRate: 48_000, durationSec: 0.12, freq: 440)

        let pack = try SoundPackImporter.importPack(from: tmpDir)
        defer { SoundPackImporter.deletePack(id: pack.metadata.id) }

        XCTAssertTrue(pack.metadata.hasKeyUpSounds)
        XCTAssertEqual(pack.categoryDown[.space]?.count, 1)
        XCTAssertEqual(pack.categoryDown[.enter]?.count, 1)
        XCTAssertFalse(pack.fallbackUp.isEmpty)
    }

    // MARK: - 4. AppSettings Persistence & AudioEngine Smoke Test

    func testAppSettingsCodableRoundTrip() throws {
        var settings = AppSettings()
        settings.activeProfile = .builtIn(.oilKing)
        settings.volume = 0.65
        settings.pitchShift = 0.92
        settings.stereoWidth = 0.85
        settings.globalHotKey = .ctrlShiftM
        settings.excludedApps = [ExcludedApp(bundleIdentifier: "us.zoom.xos", displayName: "Zoom")]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testAudioEngineProfileSwitchingAndDispatchDoesNotCrash() {
        let engine = AudioEngine()
        let settings = AppSettings()
        engine.updateParameters(from: settings)
        engine.setMuted(false)

        for sw in BuiltInSwitch.allCases {
            engine.selectBuiltIn(sw)
            engine.playKeyIfUnmuted(keyCode: 0, isDown: true)
            engine.playKeyIfUnmuted(keyCode: 0, isDown: false)
            engine.playKeyIfUnmuted(keyCode: 49, isDown: true)
            engine.playKeyIfUnmuted(keyCode: 49, isDown: false)
        }

        engine.setMuted(true)
        engine.playKeyIfUnmuted(keyCode: 36, isDown: true)

        // Allow async audio queue operations to drain cleanly
        let exp = expectation(description: "Drain audio queue")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - Helpers

    private func verifyClipHealth(_ clip: SampleClip, label: String) -> Float {
        var peak: Float = 0
        for s in clip.samples {
            XCTAssertTrue(s.isFinite, "Non-finite sample in \(label)")
            let a = abs(s)
            if a > peak { peak = a }
        }
        let tail = clip.samples.suffix(240)
        let tailMax = tail.map(abs).max() ?? 0
        XCTAssertLessThan(tailMax, 0.02, "Clip tail should fade cleanly to silence in \(label)")
        return peak
    }

    private func highFreqRatio(_ samples: [Float]) -> Float {
        guard samples.count > 2 else { return 0 }
        let slice = Array(samples.prefix(1600))
        var totalEnergy: Float = 1e-6
        var diffEnergy: Float = 0
        for i in 1..<slice.count {
            totalEnergy += slice[i] * slice[i]
            let d = slice[i] - slice[i - 1]
            diffEnergy += d * d
        }
        return diffEnergy / totalEnergy
    }

    private func makeTempDir(_ prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyClackTests-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTestWav(to url: URL, sampleRate: Double, durationSec: Double, freq: Double) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(sampleRate * durationSec)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            ptr[i] = Float(sin(2.0 * Double.pi * freq * t) * 0.5)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
