//
//  VideoImportViewModel.swift
//  Framwise
//
//  Handles video import and scene detection
//

import Foundation
import AVFoundation
import Combine

@MainActor
class VideoImportViewModel: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: Double = 0
    @Published var statusMessage = ""
    @Published var error: Error?

    // Progressive import state
    @Published var currentVideoName: String = ""
    @Published var clipsFoundCount: Int = 0
    @Published var analyzingProgress: Double = 0
    @Published var isAnalyzing: Bool = false

    private let sceneDetector = SceneDetector()
    private let maxSegmentDuration: Double = 5.0  // 5秒切割长镜头

    // MARK: - Streaming Import

    func importVideosStreaming(from urls: [URL], into session: ImportSession) async {
        isImporting = true
        isAnalyzing = true
        error = nil
        statusMessage = "Importing videos..."
        clipsFoundCount = 0

        defer {
            isImporting = false
            isAnalyzing = false
            importProgress = 1.0
            analyzingProgress = 1.0
        }

        do {
            for (index, url) in urls.enumerated() {
                importProgress = Double(index) / Double(urls.count)
                currentVideoName = url.lastPathComponent
                statusMessage = "Processing \(url.lastPathComponent)..."

                // 验证文件
                try validateVideoFile(url)

                // 添加源文件
                session.addSourceFile(url)

                // 流式分析并逐个添加clips
                try await analyzeVideoStreaming(url, into: session)
            }

            session.isAnalyzed = true
            statusMessage = "Import complete: \(session.clipCount) clips"
        } catch {
            self.error = error
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Streaming Video Analysis

    private func analyzeVideoStreaming(_ url: URL, into session: ImportSession) async throws {
        let asset = AVAsset(url: url)

        // 加载tracks
        try await asset.loadTracks(withMediaType: .video)

        statusMessage = "Analyzing \(url.lastPathComponent)..."

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // 使用流式场景检测
        let stream = await sceneDetector.detectScenesStream(in: asset)

        var sceneChanges: [CMTime] = [CMTime.zero]
        var lastProcessedTime: CMTime = .zero

        for await event in stream {
            switch event {
            case .sceneChange(let time):
                sceneChanges.append(time)

                // 立即为新的场景段创建clips
                let newSegments = createSegments(
                    from: lastProcessedTime,
                    to: time,
                    sourceURL: url,
                    maxDuration: maxSegmentDuration
                )

                for segment in newSegments {
                    let clip = segment.toVideoClip()
                    session.addClip(clip)
                    clipsFoundCount += 1
                }
                lastProcessedTime = time

            case .progress(let ratio):
                analyzingProgress = ratio

            case .frameSkipped(let time, let reason):
                // Log skipped frames for debugging (non-blocking)
                #if DEBUG
                print("[VideoImport] Frame skipped at \(time)s: \(reason)")
                #endif

            case .completed(let finalSceneChanges):
                // 处理最后一段
                let finalSegments = createSegments(
                    from: lastProcessedTime,
                    to: duration,
                    sourceURL: url,
                    maxDuration: maxSegmentDuration
                )

                for segment in finalSegments {
                    let clip = segment.toVideoClip()
                    session.addClip(clip)
                    clipsFoundCount += 1
                }

            case .error(let error):
                throw error
            }
        }
    }

    // MARK: - Legacy Import (保留兼容)

    func importVideos(from urls: [URL], into session: ImportSession) async {
        isImporting = true
        error = nil
        statusMessage = "Importing videos..."

        do {
            for (index, url) in urls.enumerated() {
                importProgress = Double(index) / Double(urls.count)
                statusMessage = "Processing \(url.lastPathComponent)..."

                // 验证文件
                try validateVideoFile(url)

                // 添加源文件
                session.addSourceFile(url)

                // 分析并生成clips
                let clips = try await analyzeVideo(url)
                session.addClips(clips)
            }

            session.isAnalyzed = true
            statusMessage = "Import complete: \(session.clipCount) clips"
        } catch {
            self.error = error
            statusMessage = "Error: \(error.localizedDescription)"
        }

        isImporting = false
        importProgress = 1.0
    }

    // MARK: - Video Analysis

    private func analyzeVideo(_ url: URL) async throws -> [VideoClip] {
        let asset = AVAsset(url: url)

        // 加载tracks
        try await asset.loadTracks(withMediaType: .video)

        // 检测场景变化点
        statusMessage = "Detecting scenes in \(url.lastPathComponent)..."
        let sceneChanges = try await sceneDetector.detectScenes(in: asset)

        // 根据场景变化生成clip segments
        let segments = try await generateClipSegments(
            from: asset,
            sceneChanges: sceneChanges,
            sourceURL: url
        )

        return segments.map { $0.toVideoClip() }
    }

    /// 根据场景变化和时间切割生成片段
    private func generateClipSegments(
        from asset: AVAsset,
        sceneChanges: [CMTime],
        sourceURL: URL
    ) async throws -> [ClipSegment] {
        var segments: [ClipSegment] = []

        let duration: CMTime
        if #available(macOS 13.0, *) {
            duration = try await asset.load(.duration)
        } else {
            duration = asset.duration
        }
        var currentTime = CMTime.zero

        // 获取场景变化点（已有时间点）
        let cutPoints = sceneChanges.sorted { CMTimeCompare($0, $1) < 0 }

        for cutPoint in cutPoints {
            // 如果当前到cut点之间超过5秒，需要再切割
            let segmentSegments = createSegments(
                from: currentTime,
                to: cutPoint,
                sourceURL: sourceURL,
                maxDuration: maxSegmentDuration
            )
            segments.append(contentsOf: segmentSegments)
            currentTime = cutPoint
        }

        // 处理最后一段
        let finalSegments = createSegments(
            from: currentTime,
            to: duration,
            sourceURL: sourceURL,
            maxDuration: maxSegmentDuration
        )
        segments.append(contentsOf: finalSegments)

        return segments
    }

    /// 创建片段，如果超过maxDuration则切割
    private func createSegments(
        from start: CMTime,
        to end: CMTime,
        sourceURL: URL,
        maxDuration: Double
    ) -> [ClipSegment] {
        var segments: [ClipSegment] = []
        let totalDuration = CMTimeGetSeconds(end) - CMTimeGetSeconds(start)

        guard totalDuration > 0.1 else { return segments }

        // 如果时长超过maxDuration，切割成多段
        if totalDuration > maxDuration {
            var currentStart = start
            let segmentDuration = CMTime(seconds: maxDuration, preferredTimescale: 600)

            while CMTimeCompare(currentStart, end) < 0 {
                let segmentEnd = CMTimeCompare(
                    CMTimeAdd(currentStart, segmentDuration),
                    end
                ) < 0 ? CMTimeAdd(currentStart, segmentDuration) : end

                segments.append(ClipSegment(
                    sourceURL: sourceURL,
                    startTime: currentStart,
                    endTime: segmentEnd
                ))

                currentStart = segmentEnd
            }
        } else {
            segments.append(ClipSegment(
                sourceURL: sourceURL,
                startTime: start,
                endTime: end
            ))
        }

        return segments
    }

    // MARK: - Validation

    private func validateVideoFile(_ url: URL) throws {
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.fileNotFound(url)
        }

        // 检查是否是支持的格式
        let supportedExtensions = ["mp4", "mov", "mxf", "avi", "mkv", "m4v"]
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw ImportError.unsupportedFormat(ext)
        }
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case fileNotFound(URL)
    case unsupportedFormat(String)
    case invalidVideo
    case analysisFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .unsupportedFormat(let ext):
            return "Unsupported format: .\(ext)"
        case .invalidVideo:
            return "Invalid or corrupted video file"
        case .analysisFailed(let reason):
            return "Analysis failed: \(reason)"
        }
    }
}
