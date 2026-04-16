//
//  ExportViewModel.swift
//  Framwise
//
//  Handles export to EDL and XML formats
//

import Foundation
import AVFoundation

@MainActor
class ExportViewModel: ObservableObject {
    @Published var isExporting = false
    @Published var exportFormat: ExportFormat = .edl
    @Published var error: Error?
    @Published var warning: String?
    var videoInfoLoader: (URL) async throws -> SourceVideoInfo = { url in
        try await ExportViewModel.loadVideoInfo(for: url)
    }

    enum ExportFormat: String, CaseIterable {
        case edl = "EDL"
        case fcpxml = "FCPXML"

        var fileExtension: String {
            switch self {
            case .edl: return "edl"
            case .fcpxml: return "fcpxml"
            }
        }

        var displayName: String {
            switch self {
            case .edl: return "EDL (CMX 3600)"
            case .fcpxml: return "FCPXML (DaVinci/FCP)"
            }
        }
    }

    // MARK: - Export

    func export(clips: [VideoClip], format: ExportFormat) async -> URL? {
        isExporting = true
        error = nil
        warning = nil

        do {
            let content: String
            let fileExtension = format.fileExtension

            switch format {
            case .edl:
                content = try await generateEDL(from: clips)
            case .fcpxml:
                content = try await generateFCPXML(from: clips)
            }

            // 保存到隔离的临时子目录
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Framwise_Export", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileName = generateExportFileName(from: clips, fileExtension: fileExtension)
            let fileURL = tempDir.appendingPathComponent(fileName)

            try content.write(to: fileURL, atomically: true, encoding: .utf8)

            return fileURL
        } catch {
            self.error = error
            return nil
        }
    }

    // MARK: - File Name Generation

    func generateExportFileName(from clips: [VideoClip], fileExtension: String) -> String {
        // 获取所有唯一的源文件
        let sourceFiles = Set(clips.map { $0.sourceFileURL })

        // 如果所有切片来自同一个源文件，使用源文件名作为前缀
        if sourceFiles.count == 1, let sourceURL = sourceFiles.first {
            let sourceName = sourceURL.deletingPathExtension().lastPathComponent
            return "\(sourceName)_export.\(fileExtension)"
        }

        // 多个源文件时，使用默认文件名
        let timestamp = Date().formatted(.iso8601.dateSeparator(.dash).timeSeparator(.colon))
        return "Framwise_Export_\(timestamp).\(fileExtension)"
    }

    // MARK: - EDL Generation (CMX 3600)

    func generateEDL(from clips: [VideoClip]) async throws -> String {
        // Load frame rate per source video for accurate timecodes
        let sourceURLs = clips.map { $0.sourceFileURL }.uniqued()

        // Parallel load all source video metadata
        let infoResults: [(index: Int, info: SourceVideoInfo)] = await withTaskGroup(of: (Int, SourceVideoInfo?).self) { group in
            for (index, url) in sourceURLs.enumerated() {
                group.addTask {
                    let info = try? await self.videoInfoLoader(url)
                    return (index, info)
                }
            }
            var results: [(index: Int, info: SourceVideoInfo)] = []
            for await (index, maybeInfo) in group {
                if let info = maybeInfo {
                    results.append((index, info))
                }
            }
            return results.sorted { $0.index < $1.index }
        }

        // Build URL → frameRate lookup (fallback to 24.0 for inaccessible files)
        let frameRateMap: [URL: Double] = Dictionary(uniqueKeysWithValues: sourceURLs.enumerated().compactMap { (index, url) -> (URL, Double)? in
            guard let info = infoResults.first(where: { $0.index == index }) else { return nil }
            return (url, info.info.frameRate)
        })

        // FCM header: prefer first source video's frame rate; if inaccessible,
        // scan remaining loaded videos for a DF rate before falling back to 24.0
        let primaryFrameRate: Double
        if let firstRate = frameRateMap[sourceURLs.first ?? URL(fileURLWithPath: "/")] {
            primaryFrameRate = firstRate
        } else if let dfRate = frameRateMap.values.first(where: { abs($0 - 29.97) < 0.01 || abs($0 - 59.94) < 0.01 }) {
            primaryFrameRate = dfRate
        } else if let anyRate = frameRateMap.values.first {
            primaryFrameRate = anyRate
        } else {
            primaryFrameRate = 24.0
        }
        let isDropFrame = abs(primaryFrameRate - 29.97) < 0.01 || abs(primaryFrameRate - 59.94) < 0.01
        let fcmHeader = isDropFrame ? "FCM: DROP FRAME" : "FCM: NON-DROP FRAME"

        var edl = """
        TITLE: Framwise Export
        \(fcmHeader)

        """

        // Rec timeline: for DF rates, count at nominal rate (30fps) to keep
        // timecodes aligned with real time; for NDF rates, use actual rate.
        let recCountRate: Double = isDropFrame ? round(primaryFrameRate) : primaryFrameRate

        var recFrameCount: Int = 0
        var eventIndex = 0
        var skippedInaccessible = 0
        let accessibleClipCount = clips.filter { frameRateMap[$0.sourceFileURL] != nil }.count

        if !clips.isEmpty && accessibleClipCount == 0 {
            throw ExportError.allClipsInaccessible(format: .edl)
        }

        for clip in clips {
            // Skip clips whose source file metadata could not be loaded
            guard frameRateMap[clip.sourceFileURL] != nil else {
                skippedInaccessible += 1
                continue
            }
            eventIndex += 1
            let eventNumber = String(format: "%03d", eventIndex)

            // Reel name: ASCII-safe, 8 chars max (CMX 3600 standard)
            // Replace non-ASCII with underscore, then truncate/pad to 8 chars
            let asciiName = clip.sourceFileName.unicodeScalars.map { scalar in
                scalar.isASCII && scalar.value >= 0x20 && scalar.value < 0x7F ? Character(scalar) : "_"
            }
            let reelName = String(asciiName.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)

            // Source timecodes: respect EDL's FCM mode (DF or NDF)
            let clipFrameRate = frameRateMap[clip.sourceFileURL] ?? 24.0
            let tcIn = TimecodeUtils.formatTimecodeEDL(clip.timecodeStart, frameRate: clipFrameRate, edlDropFrame: isDropFrame)
            let tcOut = TimecodeUtils.formatTimecodeEDL(clip.timecodeEnd, frameRate: clipFrameRate, edlDropFrame: isDropFrame)

            // Rec timecodes: frame counting at recCountRate to avoid float drift
            let clipDurationFrames = Int(round(clip.duration * recCountRate))
            let recInFrame = recFrameCount
            recFrameCount += clipDurationFrames

            let recIn = TimecodeUtils.formatTimecodeEDL(
                TimecodeUtils.time(from: recInFrame, frameRate: recCountRate),
                frameRate: primaryFrameRate,
                edlDropFrame: isDropFrame
            )
            let recOut = TimecodeUtils.formatTimecodeEDL(
                TimecodeUtils.time(from: recFrameCount, frameRate: recCountRate),
                frameRate: primaryFrameRate,
                edlDropFrame: isDropFrame
            )

            edl += """
            \(eventNumber)  \(reelName)   V     C        \(tcIn) \(tcOut) \(recIn) \(recOut)
            * FROM CLIP NAME: \(clip.sourceFileName)
            * FROM PATH: \(clip.sourceFileURL.path)

            """
        }

        if skippedInaccessible > 0 {
            warning = "\(skippedInaccessible) clip(s) skipped — source file inaccessible."
        }

        return edl
    }

    // MARK: - FCPXML Generation

    /// Source video metadata loaded for FCPXML export
    struct SourceVideoInfo {
        let url: URL
        let duration: Double
        let frameRate: Double
        let width: Int
        let height: Int
    }

    func generateFCPXML(from clips: [VideoClip]) async throws -> String {
        // Unique source URLs in stable order
        let sourceURLs = clips.map { $0.sourceFileURL }.uniqued()

        // Load metadata for each source video (parallel)
        let indexedResults: [(index: Int, info: SourceVideoInfo)] = await withTaskGroup(of: (Int, SourceVideoInfo?).self) { group in
            for (index, url) in sourceURLs.enumerated() {
                group.addTask {
                    let info = try? await self.videoInfoLoader(url)
                    return (index, info)
                }
            }
            var results: [(index: Int, info: SourceVideoInfo)] = []
            for await (index, maybeInfo) in group {
                if let info = maybeInfo {
                    results.append((index, info))
                }
            }
            return results.sorted { $0.index < $1.index }
        }

        // Check for inaccessible source videos
        let loadedIndices = Set(indexedResults.map { $0.index })
        let failedURLs = sourceURLs.enumerated()
            .filter { !loadedIndices.contains($0.offset) }
            .map { $0.element.lastPathComponent }
        if !failedURLs.isEmpty {
            warning = "Could not read metadata for: \(failedURLs.joined(separator: ", ")). Affected clips will be skipped."
        }

        let videoInfos = indexedResults.map { $0.info }
        let accessibleClipCount = clips.filter { clip in
            videoInfos.contains(where: { $0.url == clip.sourceFileURL })
        }.count

        if !clips.isEmpty && accessibleClipCount == 0 {
            throw ExportError.allClipsInaccessible(format: .fcpxml)
        }

        // Use first video's properties for the sequence format
        let primaryInfo = videoInfos.first
        let frameRate = primaryInfo?.frameRate ?? 24.0
        let width = primaryInfo?.width ?? 1920
        let height = primaryInfo?.height ?? 1080

        return buildFCPXMLString(clips: clips, videoInfos: videoInfos, frameRate: frameRate, width: width, height: height)
    }

    private static func loadVideoInfo(for url: URL) async throws -> SourceVideoInfo {
        let asset = AVAsset(url: url)
        let duration: CMTime
        if #available(macOS 13.0, *) {
            duration = try await asset.load(.duration)
        } else {
            duration = asset.duration
        }

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            return SourceVideoInfo(url: url, duration: CMTimeGetSeconds(duration), frameRate: 24, width: 1920, height: 1080)
        }

        let frameRate: Double
        let naturalSize: CGSize
        if #available(macOS 13.0, *) {
            frameRate = try await Double(track.load(.nominalFrameRate))
            naturalSize = try await track.load(.naturalSize)
        } else {
            frameRate = Double(track.nominalFrameRate)
            naturalSize = track.naturalSize
        }

        return SourceVideoInfo(
            url: url,
            duration: CMTimeGetSeconds(duration),
            frameRate: frameRate > 0 ? frameRate : 24,
            width: Int(naturalSize.width) > 0 ? Int(naturalSize.width) : 1920,
            height: Int(naturalSize.height) > 0 ? Int(naturalSize.height) : 1080
        )
    }

    func buildFCPXMLString(clips: [VideoClip], videoInfos: [SourceVideoInfo], frameRate: Double, width: Int, height: Int) -> String {
        let totalDuration = clips.reduce(0.0) { $0 + $1.duration }

        // Build URL → assetId mapping (stable, ordered)
        let assetIdMap: [URL: String] = Dictionary(uniqueKeysWithValues: videoInfos.enumerated().map { (i, info) in
            (info.url, "r\(i + 1)")
        })

        // Compute format attributes from actual video properties
        let formatName = "FFVideoFormat\(height)p\(Int(round(frameRate)))"

        // Frame duration: use FCPXML-standard rational form for NTSC rates
        let frameDurationNum: Int
        let frameDurationDenom: Int
        if abs(frameRate - 29.97) < 0.01 {
            frameDurationNum = 1001
            frameDurationDenom = 30000
        } else if abs(frameRate - 59.94) < 0.01 {
            frameDurationNum = 1001
            frameDurationDenom = 60000
        } else {
            frameDurationNum = 100
            frameDurationDenom = Int(round(frameRate * 100))
        }
        let isDropFrame = abs(frameRate - 29.97) < 0.01 || abs(frameRate - 59.94) < 0.01
        let tcFormat = isDropFrame ? "DF" : "NDF"

        // Convert seconds to frame-accurate FCPXML time string (e.g., "100/2400s")
        let framesPerSecond = frameDurationDenom
        let frameDurationNumValue = frameDurationNum
        func fcpxmlTime(_ seconds: Double) -> String {
            let totalTicks = Int(round(seconds * Double(framesPerSecond) / Double(frameDurationNumValue)))
            let rawNum = totalTicks * frameDurationNumValue
            let g = gcd(rawNum, framesPerSecond)
            return "\(rawNum / g)/\(framesPerSecond / g)s"
        }

        func gcd(_ a: Int, _ b: Int) -> Int {
            var a = abs(a), b = abs(b)
            while b != 0 { (a, b) = (b, a % b) }
            return a
        }

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
            <resources>
                <format id="r_fmt" name="\(formatName)" frameDuration="\(frameDurationNum)/\(frameDurationDenom)s" width="\(width)" height="\(height)"/>

        """

        // Add asset resources
        for info in videoInfos {
            let assetId = assetIdMap[info.url] ?? "r_unknown"

            xml += """
                    <asset id="\(xmlEscaped(assetId))" name="\(xmlEscaped(info.url.lastPathComponent))" src="\(xmlEscaped(info.url.absoluteString))" duration="\(fcpxmlTime(info.duration))">
                        <metadata>
                            <md key="com.apple.proapps.studio.clip.name" value="\(xmlEscaped(info.url.lastPathComponent))"/>
                        </metadata>
                    </asset>

            """
        }

        xml += """
            </resources>
            <library>
                <event name="Framwise Export">
                    <project name="Selected Clips">
                        <sequence format="r_fmt" duration="\(fcpxmlTime(totalDuration))" tcStart="0s" tcFormat="\(tcFormat)">
                            <spine>
        """

        // Add clips to timeline
        var currentOffset: Double = 0
        var skippedClipCount = 0

        for clip in clips {
            guard let assetId = assetIdMap[clip.sourceFileURL] else {
                skippedClipCount += 1
                continue
            }

            let startTime = CMTimeGetSeconds(clip.timecodeStart)
            let duration = clip.duration
            let offset = currentOffset

            xml += """
                                <asset-clip name="\(xmlEscaped(clip.sourceFileName))" offset="\(fcpxmlTime(offset))" ref="\(xmlEscaped(assetId))" duration="\(fcpxmlTime(duration))" start="\(fcpxmlTime(startTime))"/>

            """

            currentOffset += duration
        }

        if skippedClipCount > 0 {
            let skipMsg = "\(skippedClipCount) clip(s) skipped due to inaccessible source files."
            warning = warning.map { $0 + " " + skipMsg } ?? skipMsg
        }

        xml += """
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """

        return xml
    }

    // MARK: - XML Escaping

    func xmlEscaped(_ string: String) -> String {
        // Filter out XML 1.0 illegal control characters (0x00-0x1F except TAB/LF/CR, and 0x7F)
        let filtered = string.unicodeScalars.filter { scalar in
            if scalar.value < 0x20 {
                return scalar == "\t" || scalar == "\n" || scalar == "\r"
            }
            return scalar.value != 0x7F
        }.map(String.init).joined()

        return filtered
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

enum ExportError: LocalizedError {
    case allClipsInaccessible(format: ExportViewModel.ExportFormat)

    var errorDescription: String? {
        switch self {
        case .allClipsInaccessible(let format):
            return "Could not export \(format.rawValue): metadata could not be read for any selected source files."
        }
    }
}

// MARK: - Array uniqued helper

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}