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

            // 保存到临时文件
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = generateExportFileName(from: clips, fileExtension: fileExtension)
            let fileURL = tempDir.appendingPathComponent(fileName)

            try content.write(to: fileURL, atomically: true, encoding: .utf8)

            isExporting = false
            return fileURL
        } catch {
            self.error = error
            isExporting = false
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
                    let info = try? await Self.loadVideoInfo(for: url)
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

        // FCM header uses the first source video's frame rate
        let primaryFrameRate = frameRateMap[sourceURLs.first ?? URL(fileURLWithPath: "/")] ?? 24.0
        let isDropFrame = abs(primaryFrameRate - 29.97) < 0.01 || abs(primaryFrameRate - 59.94) < 0.01
        let fcmHeader = isDropFrame ? "FCM: DROP FRAME" : "FCM: NON-DROP FRAME"

        var edl = """
        TITLE: Framwise Export
        \(fcmHeader)

        """

        var recFrameCount: Int = 0

        for (index, clip) in clips.enumerated() {
            let eventNumber = String(format: "%03d", index + 1)

            // Reel name: ASCII-safe, 8 chars max (CMX 3600 standard)
            // Replace non-ASCII with underscore, then truncate/pad to 8 chars
            let asciiName = clip.sourceFileName.unicodeScalars.map { scalar in
                scalar.isASCII && scalar.value >= 0x20 && scalar.value < 0x7F ? Character(scalar) : "_"
            }
            let reelName = String(asciiName.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)

            // 每个 clip 使用其源视频的实际帧率
            let clipFrameRate = frameRateMap[clip.sourceFileURL] ?? 24.0

            // 时间码（使用该 clip 源视频的帧率）
            let tcIn = TimecodeUtils.formatTimecodeEDL(clip.timecodeStart, frameRate: clipFrameRate)
            let tcOut = TimecodeUtils.formatTimecodeEDL(clip.timecodeEnd, frameRate: clipFrameRate)

            // 时间轴时间码（使用整数帧号累积，避免浮点误差）
            let recIn = TimecodeUtils.formatTimecodeEDL(
                TimecodeUtils.time(from: recFrameCount, frameRate: primaryFrameRate),
                frameRate: primaryFrameRate
            )
            // Use source frame rate for frame-accurate duration, then convert to rec timeline frames
            let srcStartFrame = TimecodeUtils.frameNumber(from: clip.timecodeStart, frameRate: clipFrameRate)
            let srcEndFrame = TimecodeUtils.frameNumber(from: clip.timecodeEnd, frameRate: clipFrameRate)
            let srcDurationFrames = srcEndFrame - srcStartFrame
            let clipDurationFrames = srcDurationFrames  // Reel time: frame count is frame-rate-independent
            recFrameCount += clipDurationFrames
            let recOut = TimecodeUtils.formatTimecodeEDL(
                TimecodeUtils.time(from: recFrameCount, frameRate: primaryFrameRate),
                frameRate: primaryFrameRate
            )

            edl += """
            \(eventNumber)  \(reelName)   V     C        \(tcIn) \(tcOut) \(recIn) \(recOut)
            * FROM CLIP NAME: \(clip.sourceFileName)
            * FROM PATH: \(clip.sourceFileURL.path)

            """
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
                    let info = try? await Self.loadVideoInfo(for: url)
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

        // Check for inaccessible source videos (use fallback values instead of failing)
        let loadedIndices = Set(indexedResults.map { $0.index })
        let failedURLs = sourceURLs.enumerated()
            .filter { !loadedIndices.contains($0.offset) }
            .map { $0.element.lastPathComponent }
        if !failedURLs.isEmpty {
            warning = "Could not read metadata for: \(failedURLs.joined(separator: ", ")). Using default values."
        }

        let videoInfos = indexedResults.map { $0.info }

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
        let frameDurationNum = 100
        let frameDurationDenom = Int(round(frameRate * 100))
        let isDropFrame = abs(frameRate - 29.97) < 0.01 || abs(frameRate - 59.94) < 0.01
        let tcFormat = isDropFrame ? "DF" : "NDF"

        // Convert seconds to frame-accurate FCPXML time string (e.g., "1200/2400s")
        let framesPerSecond = frameDurationDenom
        let frameDurationNumValue = frameDurationNum
        func fcpxmlTime(_ seconds: Double) -> String {
            let totalFrames = Int(round(seconds * Double(framesPerSecond) / Double(frameDurationNumValue)))
            let wholePart = totalFrames / framesPerSecond
            let remainder = totalFrames % framesPerSecond
            if remainder == 0 {
                return "\(wholePart * frameDurationNumValue)/\(framesPerSecond)s"
            }
            // Reduce fraction using GCD
            let g = gcd(remainder, framesPerSecond)
            let num = (wholePart * framesPerSecond + remainder) / g * frameDurationNumValue
            let den = framesPerSecond / g
            return "\(num)/\(den)s"
        }

        func gcd(_ a: Int, _ b: Int) -> Int {
            var a = a, b = b
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

        for clip in clips {
            guard let assetId = assetIdMap[clip.sourceFileURL] else {
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

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case sourceFilesInaccessible([String])

    var errorDescription: String? {
        switch self {
        case .sourceFilesInaccessible(let names):
            return "Cannot read video files: \(names.joined(separator: ", ")). The files may have been moved or deleted."
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