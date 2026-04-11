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
            case .fcpxml: return "FCPXML (DaVinci/PR)"
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

    func generateFCPXML(from clips: [VideoClip]) async throws -> String {
        // 获取所有唯一的源文件
        let sourceFiles = Dictionary(grouping: clips) { $0.sourceFileURL }

        // 加载每个源文件的时长
        var assetDurations: [URL: Double] = [:]
        for url in sourceFiles.keys {
            let asset = AVAsset(url: url)
            if #available(macOS 13.0, *) {
                assetDurations[url] = CMTimeGetSeconds(try await asset.load(.duration))
            } else {
                assetDurations[url] = CMTimeGetSeconds(asset.duration)
            }
        }

        return buildFCPXMLString(clips: clips, assetDurations: assetDurations)
    }

    func buildFCPXMLString(clips: [VideoClip], assetDurations: [URL: Double]) -> String {
        let sourceFiles = Dictionary(grouping: clips) { $0.sourceFileURL }

        // 计算总时长
        let totalDuration = clips.reduce(0.0) { $0 + $1.duration }

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
            <resources>
                <format id="r1001" name="FFVideoFormat1080p24" frameDuration="100/2400s" width="1920" height="1080"/>

        """

        // 添加资源
        for (index, (url, _)) in sourceFiles.enumerated() {
            let duration = assetDurations[url] ?? 0
            let assetId = "r\(index + 1)"

            xml += """
                    <asset id="\(xmlEscaped(assetId))" name="\(xmlEscaped(url.lastPathComponent))" src="file://\(xmlEscaped(url.path))" duration="\(duration)s">
                        <metadata>
                            <md key="com.apple.proapps.studio.clip.name" value="\(xmlEscaped(url.lastPathComponent))"/>
                        </metadata>
                    </asset>

            """
        }

        xml += """
            </resources>
            <library>
                <event name="Framwise Export">
                    <project name="Selected Clips">
                        <sequence format="r1001" duration="\(totalDuration)s" tcStart="0s">
                            <spine>
        """

        // 添加clips到时间轴
        var currentOffset: Double = 0

        for clip in clips {
            guard let assetIndex = sourceFiles.keys.enumerated().first(where: { $0.element == clip.sourceFileURL })?.offset else {
                continue
            }

            let assetId = "r\(assetIndex + 1)"
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