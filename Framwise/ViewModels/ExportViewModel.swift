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

        do {
            let content: String
            let fileExtension = format.fileExtension

            switch format {
            case .edl:
                content = try generateEDL(from: clips)
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

    func generateEDL(from clips: [VideoClip]) throws -> String {
        var edl = """
        TITLE: Framwise Export
        FCM: NON-DROP FRAME

        """

        var recTime: CMTime = .zero

        for (index, clip) in clips.enumerated() {
            let eventNumber = String(format: "%03d", index + 1)

            // 原始素材名称（截断为8字符）
            let reelName = String(clip.sourceFileName.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)

            // 时间码
            let tcIn = TimecodeUtils.formatTimecodeEDL(clip.timecodeStart)
            let tcOut = TimecodeUtils.formatTimecodeEDL(clip.timecodeEnd)

            // 时间轴时间码（累积，O(1)）
            let recIn = TimecodeUtils.formatTimecodeEDL(recTime)
            recTime = CMTimeAdd(recTime, CMTimeSubtract(clip.timecodeEnd, clip.timecodeStart))
            let recOut = TimecodeUtils.formatTimecodeEDL(recTime)

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
        let videoInfos: [SourceVideoInfo] = await withTaskGroup(of: SourceVideoInfo?.self) { group in
            for url in sourceURLs {
                group.addTask {
                    guard let info = try? await Self.loadVideoInfo(for: url) else { return nil }
                    return info
                }
            }
            var results: [SourceVideoInfo] = []
            for await info in group.compactMap({ $0 }) {
                results.append(info)
            }
            return results.sorted { sourceURLs.firstIndex(of: $0.url) ?? 0 < sourceURLs.firstIndex(of: $1.url) ?? 0 }
        }

        // Use first video's properties for the sequence format, fallback to 1080p24
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
                    <asset id="\(xmlEscaped(assetId))" name="\(xmlEscaped(info.url.lastPathComponent))" src="\(xmlEscaped(info.url.absoluteString))" duration="\(info.duration)s">
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
                        <sequence format="r_fmt" duration="\(totalDuration)s" tcStart="0s" tcFormat="\(tcFormat)">
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
                                <asset-clip name="\(xmlEscaped(clip.sourceFileName))" offset="\(offset)s" ref="\(xmlEscaped(assetId))" duration="\(duration)s" start="\(startTime)s"/>

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
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Array uniqued helper

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}