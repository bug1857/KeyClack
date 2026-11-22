import Foundation
import AVFoundation

/// A loaded user sound pack ready for zero-latency playback by AudioEngine.
struct LoadedSoundPack {
    let metadata: ImportedSoundPack
    let perKeyDown: [UInt16: [SampleClip]]
    let perKeyUp: [UInt16: [SampleClip]]
    let categoryDown: [KeyCategory: [SampleClip]]
    let categoryUp: [KeyCategory: [SampleClip]]
    let fallbackDown: [SampleClip]
    let fallbackUp: [SampleClip]

    func clip(for keyCode: UInt16, category: KeyCategory, isDown: Bool, cycleIndex: Int) -> SampleClip? {
        if isDown {
            if let clips = perKeyDown[keyCode], !clips.isEmpty {
                return clips[cycleIndex % clips.count]
            }
            if let clips = categoryDown[category], !clips.isEmpty {
                return clips[cycleIndex % clips.count]
            }
            guard !fallbackDown.isEmpty else { return nil }
            return fallbackDown[cycleIndex % fallbackDown.count]
        } else {
            if let clips = perKeyUp[keyCode], !clips.isEmpty {
                return clips[cycleIndex % clips.count]
            }
            if let clips = categoryUp[category], !clips.isEmpty {
                return clips[cycleIndex % clips.count]
            }
            if !fallbackUp.isEmpty {
                return fallbackUp[cycleIndex % fallbackUp.count]
            }
            return nil
        }
    }
}

enum SoundPackImportError: LocalizedError {
    case invalidSelection
    case unzipFailed(String)
    case noAudioFilesFound
    case oggRequiresFFmpeg
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSelection:
            return "Select a Mechvibes .zip archive, a sound pack folder, or a config.json file."
        case .unzipFailed(let detail):
            return "Could not extract ZIP archive: \(detail)"
        case .noAudioFilesFound:
            return "No usable audio files (.wav, .mp3, .m4a, .flac, .aiff, .ogg) were found in this pack."
        case .oggRequiresFFmpeg:
            return "This pack uses .ogg audio. Install ffmpeg (`brew install ffmpeg`) once to auto-convert .ogg Mechvibes packs, or use .wav/.mp3/.flac packs natively."
        case .decodeFailed(let detail):
            return "Failed to decode audio file: \(detail)"
        }
    }
}

/// Imports and loads Mechvibes V1, MechvibesDX V2, ZIP archives, and plain audio folders.
/// All imported packs are normalized and stored under ~/Library/Application Support/KeyClack/ImportedPacks/.
final class SoundPackImporter {
    static let canonicalSampleRate: Double = 48_000.0
    static let supportedNativeExtensions: Set<String> = ["wav", "mp3", "m4a", "flac", "aif", "aiff", "caf"]

    static var packsRootURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("KeyClack/ImportedPacks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Lists all previously imported packs saved in Application Support.
    static func listImportedPacks() -> [ImportedSoundPack] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: packsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [ImportedSoundPack] = []
        let decoder = JSONDecoder()
        for dir in entries {
            let metaURL = dir.appendingPathComponent("keyclack_meta.json")
            if let data = try? Data(contentsOf: metaURL),
               let meta = try? decoder.decode(ImportedSoundPack.self, from: data) {
                result.append(meta)
            }
        }
        return result.sorted { $0.importedAt > $1.importedAt }
    }

    /// Deletes an imported sound pack from disk.
    static func deletePack(id: String) {
        let target = packsRootURL.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: target)
    }

    /// Imports a `.zip`, folder, or `config.json` into Application Support and returns the loaded pack.
    static func importPack(from selectedURL: URL) throws -> LoadedSoundPack {
        let fm = FileManager.default
        var tempDir: URL?
        defer {
            if let tempDir {
                try? fm.removeItem(at: tempDir)
            }
        }

        let sourceDir: URL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: selectedURL.path, isDirectory: &isDir) else {
            throw SoundPackImportError.invalidSelection
        }

        if isDir.boolValue {
            sourceDir = selectedURL
        } else if selectedURL.pathExtension.lowercased() == "zip" {
            let tmp = fm.temporaryDirectory.appendingPathComponent("KeyClackImport-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            tempDir = tmp
            try unzipArchive(selectedURL, to: tmp)
            sourceDir = locatePackRoot(inside: tmp)
        } else if selectedURL.lastPathComponent.lowercased() == "config.json" {
            sourceDir = selectedURL.deletingLastPathComponent()
        } else {
            throw SoundPackImportError.invalidSelection
        }

        let resolvedSource = locatePackRoot(inside: sourceDir)
        let packID = "pack-\(UUID().uuidString.prefix(8).lowercased())"
        let destDir = packsRootURL.appendingPathComponent(packID, isDirectory: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        do {
            // Copy all relevant files (config.json + audio files) into our managed folder,
            // converting any .ogg files to .wav via ffmpeg so playback is always native & instant.
            try copyAndConvertPackAssets(from: resolvedSource, to: destDir)

            let defaultName = selectedURL.deletingPathExtension().lastPathComponent
            let loaded = try loadPackFromDirectory(destDir, packID: packID, fallbackName: defaultName)

            let metaData = try JSONEncoder().encode(loaded.metadata)
            try metaData.write(to: destDir.appendingPathComponent("keyclack_meta.json"))
            return loaded
        } catch {
            try? fm.removeItem(at: destDir)
            throw error
        }
    }

    /// Reloads an already-imported pack from Application Support.
    static func loadSavedPack(id: String) throws -> LoadedSoundPack {
        let dir = packsRootURL.appendingPathComponent(id, isDirectory: true)
        let metaURL = dir.appendingPathComponent("keyclack_meta.json")
        let fallbackName: String
        if let data = try? Data(contentsOf: metaURL),
           let meta = try? JSONDecoder().decode(ImportedSoundPack.self, from: data) {
            fallbackName = meta.name
        } else {
            fallbackName = id
        }
        return try loadPackFromDirectory(dir, packID: id, fallbackName: fallbackName)
    }

    // MARK: - Pack Parsing (Mechvibes V1, MechvibesDX V2, and Plain Folder)

    private static func loadPackFromDirectory(
        _ dir: URL,
        packID: String,
        fallbackName: String
    ) throws -> LoadedSoundPack {
        let configURL = dir.appendingPathComponent("config.json")
        if FileManager.default.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let rootObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if rootObj["definitions"] != nil || rootObj["defs"] != nil {
                return try parseMechvibesV2(rootObj, in: dir, packID: packID, fallbackName: fallbackName)
            } else if rootObj["defines"] != nil {
                return try parseMechvibesV1(rootObj, in: dir, packID: packID, fallbackName: fallbackName)
            }
        }
        return try parsePlainAudioFolder(dir, packID: packID, fallbackName: fallbackName)
    }

    /// Parses classic Mechvibes V1 config.json (`defines`, `sound`, `key_define_type`: "single" | "multi").
    private static func parseMechvibesV1(
        _ json: [String: Any],
        in dir: URL,
        packID: String,
        fallbackName: String
    ) throws -> LoadedSoundPack {
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let packName = (name?.isEmpty == false) ? name! : fallbackName
        let author = (json["author"] as? String) ?? "Mechvibes Community"
        let mode = (json["key_define_type"] as? String)?.lowercased() ?? "single"
        let defines = (json["defines"] as? [String: Any]) ?? [:]

        var perKeyDown: [UInt16: [SampleClip]] = [:]
        var allDown: [SampleClip] = []

        if mode == "multi" {
            var fileCache: [String: SampleClip] = [:]
            for (rawCode, value) in defines {
                guard let filename = value as? String, !filename.isEmpty else { continue }
                guard let clip = try cachedDecode(filename: filename, in: dir, cache: &fileCache) else { continue }
                allDown.append(clip)
                if let intCode = Int(rawCode), let macCode = KeyLayoutMap.macKeyCode(fromV1Code: intCode) {
                    perKeyDown[macCode, default: []].append(clip)
                }
            }
        } else {
            let soundFileName = (json["sound"] as? String) ?? findFirstAudioFilename(in: dir) ?? ""
            guard let fullSamples = try decodeAudioFile(named: soundFileName, in: dir) else {
                throw SoundPackImportError.noAudioFilesFound
            }
            for (rawCode, value) in defines {
                guard let arr = value as? [Any], arr.count >= 2,
                      let startMs = toDouble(arr[0]),
                      let durationMs = toDouble(arr[1]),
                      durationMs > 5 else { continue }

                // Classic Mechvibes V1 uses [start_ms, duration_ms]
                if let clip = sliceSamples(fullSamples, startMs: startMs, durationMs: durationMs) {
                    allDown.append(clip)
                    if let intCode = Int(rawCode), let macCode = KeyLayoutMap.macKeyCode(fromV1Code: intCode) {
                        perKeyDown[macCode, default: []].append(clip)
                    }
                }
            }
        }

        guard !allDown.isEmpty else {
            throw SoundPackImportError.noAudioFilesFound
        }

        let categoryDown = buildCategoryFallbacks(from: perKeyDown)
        let meta = ImportedSoundPack(
            id: packID,
            name: packName,
            author: author,
            formatDescription: "Mechvibes V1 (\(mode))",
            hasKeyUpSounds: false,
            keyCount: perKeyDown.count,
            importedAt: Date()
        )
        return LoadedSoundPack(
            metadata: meta,
            perKeyDown: perKeyDown,
            perKeyUp: [:],
            categoryDown: categoryDown,
            categoryUp: [:],
            fallbackDown: Array(allDown.prefix(24)),
            fallbackUp: []
        )
    }

    /// Parses MechvibesDX V2 config.json (`definitions`/`defs`, `audio_file`, `definition_method`).
    /// Supports both downstroke-only and dual-segment down+upstroke timing arrays!
    private static func parseMechvibesV2(
        _ json: [String: Any],
        in dir: URL,
        packID: String,
        fallbackName: String
    ) throws -> LoadedSoundPack {
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let packName = (name?.isEmpty == false) ? name! : fallbackName
        let author = (json["author"] as? String) ?? "Mechvibes Community"
        let method = (json["definition_method"] as? String)?.lowercased() ?? "single"
        let defs = (json["definitions"] as? [String: Any]) ?? (json["defs"] as? [String: Any]) ?? [:]

        var perKeyDown: [UInt16: [SampleClip]] = [:]
        var perKeyUp: [UInt16: [SampleClip]] = [:]
        var allDown: [SampleClip] = []
        var allUp: [SampleClip] = []

        if method == "multi" {
            var fileCache: [String: SampleClip] = [:]
            for (keyName, rawValue) in defs {
                let macCode = KeyLayoutMap.macKeyCode(fromW3CCode: keyName)
                if let filename = rawValue as? String {
                    if let clip = try cachedDecode(filename: filename, in: dir, cache: &fileCache) {
                        allDown.append(clip)
                        if let macCode { perKeyDown[macCode, default: []].append(clip) }
                    }
                } else if let dict = rawValue as? [String: Any] {
                    if let downFile = (dict["audio_file"] as? String) ?? (dict["down"] as? String),
                       let clip = try cachedDecode(filename: downFile, in: dir, cache: &fileCache) {
                        allDown.append(clip)
                        if let macCode { perKeyDown[macCode, default: []].append(clip) }
                    }
                    if let upFile = dict["up"] as? String,
                       let clip = try cachedDecode(filename: upFile, in: dir, cache: &fileCache) {
                        allUp.append(clip)
                        if let macCode { perKeyUp[macCode, default: []].append(clip) }
                    }
                }
            }
        } else {
            let audioFile = (json["audio_file"] as? String)
                ?? (json["sound"] as? String)
                ?? findFirstAudioFilename(in: dir)
                ?? ""
            guard let fullSamples = try decodeAudioFile(named: audioFile, in: dir) else {
                throw SoundPackImportError.noAudioFilesFound
            }

            for (keyName, rawValue) in defs {
                let macCode = KeyLayoutMap.macKeyCode(fromW3CCode: keyName)
                var segments: [[Double]] = []

                if let dict = rawValue as? [String: Any], let timing = dict["timing"] as? [Any] {
                    segments = extractV2Segments(timing)
                } else if let rawArr = rawValue as? [Any] {
                    segments = extractV2Segments(rawArr)
                }

                // Segment 0: Downstroke [start_ms, end_ms]
                if let downSeg = segments.first, downSeg.count >= 2 {
                    let startMs = downSeg[0]
                    let endMs = downSeg[1]
                    let durMs = max(0, endMs > startMs ? (endMs - startMs) : endMs)
                    if durMs > 5, let clip = sliceSamples(fullSamples, startMs: startMs, durationMs: durMs) {
                        allDown.append(clip)
                        if let macCode { perKeyDown[macCode, default: []].append(clip) }
                    }
                }

                // Segment 1 (optional): Upstroke [start_ms, end_ms]
                if segments.count >= 2 {
                    let upSeg = segments[1]
                    if upSeg.count >= 2 {
                        let startMs = upSeg[0]
                        let endMs = upSeg[1]
                        let durMs = max(0, endMs > startMs ? (endMs - startMs) : endMs)
                        if durMs > 5, let clip = sliceSamples(fullSamples, startMs: startMs, durationMs: durMs) {
                            allUp.append(clip)
                            if let macCode { perKeyUp[macCode, default: []].append(clip) }
                        }
                    }
                }
            }
        }

        guard !allDown.isEmpty else {
            throw SoundPackImportError.noAudioFilesFound
        }

        let meta = ImportedSoundPack(
            id: packID,
            name: packName,
            author: author,
            formatDescription: "Mechvibes V2 (\(method))",
            hasKeyUpSounds: !allUp.isEmpty,
            keyCount: perKeyDown.count,
            importedAt: Date()
        )
        return LoadedSoundPack(
            metadata: meta,
            perKeyDown: perKeyDown,
            perKeyUp: perKeyUp,
            categoryDown: buildCategoryFallbacks(from: perKeyDown),
            categoryUp: buildCategoryFallbacks(from: perKeyUp),
            fallbackDown: Array(allDown.prefix(24)),
            fallbackUp: Array(allUp.prefix(24))
        )
    }

    /// Fallback importer for a plain folder of WAV / MP3 / M4A / FLAC samples without config.json.
    private static func parsePlainAudioFolder(
        _ dir: URL,
        packID: String,
        fallbackName: String
    ) throws -> LoadedSoundPack {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let audioFiles = files.filter { supportedNativeExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var categoryDown: [KeyCategory: [SampleClip]] = [:]
        var categoryUp: [KeyCategory: [SampleClip]] = [:]
        var genericDown: [SampleClip] = []
        var genericUp: [SampleClip] = []

        for file in audioFiles {
            guard let samples = try decodeAudioURL(file) else { continue }
            // Cap individual key samples at 0.35s so a long audio clip doesn't bleed
            let capped = Array(samples.prefix(Int(canonicalSampleRate * 0.35)))
            let clip = normalizeAndFade(capped, targetPeak: 0.82)
            let lower = file.deletingPathExtension().lastPathComponent.lowercased()
            let isUp = lower.contains("up") || lower.contains("release")

            let category: KeyCategory?
            if lower.contains("space") {
                category = .space
            } else if lower.contains("enter") || lower.contains("return") {
                category = .enter
            } else if lower.contains("back") || lower.contains("delete") {
                category = .backspace
            } else if lower.contains("shift") {
                category = .shift
            } else if lower.contains("mod") || lower.contains("tab") || lower.contains("cap") {
                category = .modifier
            } else {
                category = nil
            }

            if isUp {
                if let category {
                    categoryUp[category, default: []].append(clip)
                } else {
                    genericUp.append(clip)
                }
            } else {
                if let category {
                    categoryDown[category, default: []].append(clip)
                } else {
                    genericDown.append(clip)
                }
            }
        }

        if genericDown.isEmpty {
            genericDown = categoryDown.values.flatMap { $0 }
        }
        guard !genericDown.isEmpty else {
            throw SoundPackImportError.noAudioFilesFound
        }

        let meta = ImportedSoundPack(
            id: packID,
            name: fallbackName,
            author: "Custom Audio Folder",
            formatDescription: "Custom Samples (\(audioFiles.count) files)",
            hasKeyUpSounds: !genericUp.isEmpty || !categoryUp.isEmpty,
            keyCount: audioFiles.count,
            importedAt: Date()
        )
        return LoadedSoundPack(
            metadata: meta,
            perKeyDown: [:],
            perKeyUp: [:],
            categoryDown: categoryDown,
            categoryUp: categoryUp,
            fallbackDown: genericDown,
            fallbackUp: genericUp
        )
    }

    // MARK: - Helpers

    private static func buildCategoryFallbacks(from perKey: [UInt16: [SampleClip]]) -> [KeyCategory: [SampleClip]] {
        var result: [KeyCategory: [SampleClip]] = [:]
        for (macCode, clips) in perKey {
            let cat = KeyLayoutMap.info(for: macCode).category
            if result[cat] == nil || (result[cat]?.count ?? 0) < 6 {
                result[cat, default: []].append(contentsOf: clips)
            }
        }
        return result
    }

    private static func extractV2Segments(_ arr: [Any]) -> [[Double]] {
        if let first = arr.first, first is [Any] {
            return arr.compactMap { item in
                guard let pair = item as? [Any], pair.count >= 2,
                      let a = toDouble(pair[0]), let b = toDouble(pair[1]) else { return nil }
                return [a, b]
            }
        }
        if arr.count >= 2, let a = toDouble(arr[0]), let b = toDouble(arr[1]) {
            return [[a, b]]
        }
        return []
    }

    private static func toDouble(_ any: Any) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func unzipArchive(_ zipURL: URL, to destDir: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zipURL.path, "-d", destDir.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "exit code \(process.terminationStatus)"
            throw SoundPackImportError.unzipFailed(errText)
        }
    }

    private static func locatePackRoot(inside dir: URL) -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) {
            return dir
        }
        if let children = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children where child.lastPathComponent != "__MACOSX" {
                if fm.fileExists(atPath: child.appendingPathComponent("config.json").path) {
                    return child
                }
            }
            let dirs = children.filter {
                $0.lastPathComponent != "__MACOSX" &&
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            if dirs.count == 1 {
                return dirs[0]
            }
        }
        return dir
    }

    private static func copyAndConvertPackAssets(from srcDir: URL, to destDir: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var hadOggWithoutConverter = false
        var copiedAnyAudio = false

        for item in items {
            guard (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let ext = item.pathExtension.lowercased()
            let fileName = item.lastPathComponent

            if fileName.lowercased() == "config.json" {
                try fm.copyItem(at: item, to: destDir.appendingPathComponent("config.json"))
            } else if supportedNativeExtensions.contains(ext) {
                try fm.copyItem(at: item, to: destDir.appendingPathComponent(fileName))
                copiedAnyAudio = true
            } else if ext == "ogg" {
                let wavName = item.deletingPathExtension().lastPathComponent + ".wav"
                let wavDest = destDir.appendingPathComponent(wavName)
                if convertOggToWav(inputURL: item, outputURL: wavDest) {
                    copiedAnyAudio = true
                } else {
                    hadOggWithoutConverter = true
                }
            }
        }

        if !copiedAnyAudio && hadOggWithoutConverter {
            throw SoundPackImportError.oggRequiresFFmpeg
        }
        if !copiedAnyAudio {
            throw SoundPackImportError.noAudioFilesFound
        }
    }

    private static func convertOggToWav(inputURL: URL, outputURL: URL) -> Bool {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        guard let ffmpeg = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y", "-v", "error",
            "-i", inputURL.path,
            "-ar", "48000", "-ac", "1",
            outputURL.path
        ]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputURL.path)
        } catch {
            return false
        }
    }

    private static func findFirstAudioFilename(in dir: URL) -> String? {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.first { supportedNativeExtensions.contains($0.pathExtension.lowercased()) }?.lastPathComponent
    }

    private static func cachedDecode(
        filename: String,
        in dir: URL,
        cache: inout [String: SampleClip]
    ) throws -> SampleClip? {
        if let existing = cache[filename] {
            return existing
        }
        guard let samples = try decodeAudioFile(named: filename, in: dir) else { return nil }
        let capped = Array(samples.prefix(Int(canonicalSampleRate * 0.35)))
        let clip = normalizeAndFade(capped, targetPeak: 0.82)
        cache[filename] = clip
        return clip
    }

    private static func decodeAudioFile(named filename: String, in dir: URL) throws -> [Float]? {
        let cleanName = URL(fileURLWithPath: filename).lastPathComponent
        let directURL = dir.appendingPathComponent(cleanName)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return try decodeAudioURL(directURL)
        }
        // If config.json referenced foo.ogg and we converted it to foo.wav on import:
        let wavFallback = dir.appendingPathComponent(
            URL(fileURLWithPath: cleanName).deletingPathExtension().lastPathComponent + ".wav"
        )
        if FileManager.default.fileExists(atPath: wavFallback.path) {
            return try decodeAudioURL(wavFallback)
        }
        return nil
    }

    /// Decodes any AVAudioFile-supported format and resamples to canonical 48 kHz mono Float PCM.
    private static func decodeAudioURL(_ url: URL) throws -> [Float]? {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw SoundPackImportError.decodeFailed("\(url.lastPathComponent): \(error.localizedDescription)")
        }

        let srcFormat = audioFile.processingFormat
        let srcFrames = AVAudioFrameCount(audioFile.length)
        guard srcFrames > 0,
              let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: srcFrames) else {
            return nil
        }

        do {
            try audioFile.read(into: srcBuffer)
        } catch {
            throw SoundPackImportError.decodeFailed("\(url.lastPathComponent): \(error.localizedDescription)")
        }

        guard let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: canonicalSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        let ratio = canonicalSampleRate / srcFormat.sampleRate
        let dstCapacity = AVAudioFrameCount(ceil(Double(srcBuffer.frameLength) * ratio)) + 64
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: dstCapacity),
              let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            return nil
        }

        var didSupplyInput = false
        var conversionError: NSError?
        _ = converter.convert(to: dstBuffer, error: &conversionError) { _, outStatus in
            if didSupplyInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            didSupplyInput = true
            outStatus.pointee = .haveData
            return srcBuffer
        }

        if let conversionError {
            throw SoundPackImportError.decodeFailed(conversionError.localizedDescription)
        }

        guard let channelData = dstBuffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(dstBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameCount))
    }

    private static func sliceSamples(_ full: [Float], startMs: Double, durationMs: Double) -> SampleClip? {
        let startIdx = max(0, Int((startMs / 1000.0) * canonicalSampleRate))
        let sliceLen = max(1, Int((min(durationMs, 350.0) / 1000.0) * canonicalSampleRate))
        guard startIdx < full.count else { return nil }
        let endIdx = min(full.count, startIdx + sliceLen)
        guard endIdx - startIdx > 64 else { return nil }
        let raw = Array(full[startIdx..<endIdx])
        return normalizeAndFade(raw, targetPeak: 0.82)
    }

    private static func normalizeAndFade(_ samples: [Float], targetPeak: Float) -> SampleClip {
        guard !samples.isEmpty else { return SampleClip(samples: []) }
        var out = samples
        var peak: Float = 0.0001
        for s in out {
            let a = abs(s)
            if a > peak { peak = a }
        }
        let scale = targetPeak / peak
        let fadeIn = min(72, out.count / 4)    // 1.5 ms anti-click ramp
        let fadeOut = min(288, out.count / 3)  // 6 ms clean tail fade

        for i in 0..<out.count {
            var s = out[i] * scale
            if i < fadeIn {
                s *= Float(i) / Float(fadeIn)
            }
            let fromEnd = out.count - 1 - i
            if fromEnd < fadeOut {
                s *= Float(fromEnd) / Float(fadeOut)
            }
            out[i] = s
        }
        return SampleClip(samples: out)
    }
}
