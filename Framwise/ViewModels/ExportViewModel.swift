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
            let fileName = "Framwise_Export_\(Date().formatted(.iso8601.dateSeparator(.dash).timeSeparator(.colon))).\(fileExtension)"
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

    // MARK: - EDL Generation (CMX 3600)

    private func generateEDL(from clips: [VideoClip]) throws -> String {
        var edl = """
        TITLE: Framwise Export
        FCM: NON-DROP FRAME

        """

        for (index, clip) in clips.enumerated() {
            let eventNumber = String(format: "%03d", index + 1)

            // 原始素材名称（截断为8字符）
            let reelName = String(clip.sourceFileName.prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)

            // 时间码
            let tcIn = TimecodeUtils.formatTimecodeEDL(clip.timecodeStart)
            let tcOut = TimecodeUtils.formatTimecodeEDL(clip.timecodeEnd)

            // 时间轴时间码（累积）
            let recIn = TimecodeUtils.formatTimecodeEDL(
                clips[0..<index].reduce(CMTime.zero) { CMTimeAdd($0, $1.timecodeEnd) - CMTimeAdd($0, $1.timecodeStart) }
            )
            let recOut = TimecodeUtils.formatTimecodeEDL(
                clips[0...index].reduce(CMTime.zero) { CMTimeAdd($0, $1.timecodeEnd) - CMTimeAdd($0, $1.timecodeStart) }
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

    private func generateFCPXML(from clips: [VideoClip]) async throws -> String {
        // 获取所有唯一的源文件
        let sourceFiles = Dictionary(grouping: clips) { $0.sourceFileURL }

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.9">
            <resources>
        """

        // 添加资源
        for (index, (url, _)) in sourceFiles.enumerated() {
            let asset = AVAsset(url: url)
            let duration: Double
            if #available(macOS 13.0, *) {
                duration = CMTimeGetSeconds(try await asset.load(.duration))
            } else {
                duration = CMTimeGetSeconds(asset.duration)
            }
            let assetId = "r\(index + 1)"

            xml += """
                    <asset id="\(assetId)" name="\(url.lastPathComponent)" src="file://\(url.path)" duration="\(duration)s">
                        <metadata>
                            <md key="com.apple.proapps.studio.clip.name" value="\(url.lastPathComponent)"/>
                        </metadata>
                    </asset>

            """
        }

        xml += """
            </resources>
            <library>
                <event name="Framwise Export">
                    <project name="Selected Clips">
                        <sequence format="r1001" duration="0s">
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
                                <asset-clip name="\(clip.sourceFileName)" offset="\((offset / 1.0))s" ref="\(assetId)" duration="\((duration / 1.0))s" start="\((startTime / 1.0))s"/>

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
}

// MARK: - Helper for CMTime accumulation
private extension ArraySlice where Element == VideoClip {
    func reduce(_ initial: CMTime) -> CMTime {
        reduce(initial) { result, clip in
            CMTimeAdd(result, CMTimeSubtract(clip.timecodeEnd, clip.timecodeStart))
        }
    }
}
