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
    @Published var totalFilesCount: Int = 0

    private let sceneDetector = SceneDetector()
    private let wasteDetector = WasteDetector()
    private var targetSegmentCount: Int {
        let count = UserDefaults.standard.integer(forKey: "segmentCount")
        return count > 0 ? count : 36
    }

    // MARK: - Streaming Import

    func importVideosStreaming(from urls: [URL], into session: ImportSession) async {
        isImporting = true
        isAnalyzing = true
        error = nil
        statusMessage = "Importing videos..."
        clipsFoundCount = 0
        totalFilesCount = urls.count

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
        let totalDuration = CMTimeGetSeconds(duration)

        // 使用流式场景检测
        let stream = await sceneDetector.detectScenesStream(in: asset)

        var lastProcessedTime: CMTime = .zero

        for await event in stream {
            switch event {
            case .sceneChange(let time):
                // 阶段一：按场景边界直接创建单个片段（不细分）
                let segDuration = CMTimeGetSeconds(time) - CMTimeGetSeconds(lastProcessedTime)
                if segDuration > 0.1 {
                    let segment = ClipSegment(sourceURL: url, startTime: lastProcessedTime, endTime: time)
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

            case .completed:
                // 处理最后一段
                let finalDuration = CMTimeGetSeconds(duration) - CMTimeGetSeconds(lastProcessedTime)
                if finalDuration > 0.1 {
                    let segment = ClipSegment(sourceURL: url, startTime: lastProcessedTime, endTime: duration)
                    let clip = segment.toVideoClip()
                    session.addClip(clip)
                    clipsFoundCount += 1
                }

                // 阶段二：补切长场景
                refineLongSegments(
                    session: session,
                    targetCount: targetSegmentCount,
                    sourceURL: url,
                    totalDuration: totalDuration
                )

                // 阶段三：废料检测
                await detectWasteForClips(session: session, sourceURL: url, filename: url.lastPathComponent)

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

    /// 根据场景变化生成片段（legacy 路径，使用新逻辑）
    private func generateClipSegments(
        from asset: AVAsset,
        sceneChanges: [CMTime],
        sourceURL: URL
    ) async throws -> [ClipSegment] {
        let duration: CMTime
        if #available(macOS 13.0, *) {
            duration = try await asset.load(.duration)
        } else {
            duration = asset.duration
        }

        // 按场景边界创建片段（不细分）
        var segments: [ClipSegment] = []
        let cutPoints = sceneChanges.sorted { CMTimeCompare($0, $1) < 0 }
        var currentTime = CMTime.zero

        for cutPoint in cutPoints {
            let segDuration = CMTimeGetSeconds(cutPoint) - CMTimeGetSeconds(currentTime)
            if segDuration > 0.1 {
                segments.append(ClipSegment(sourceURL: sourceURL, startTime: currentTime, endTime: cutPoint))
            }
            currentTime = cutPoint
        }

        // 最后一段
        let finalDuration = CMTimeGetSeconds(duration) - CMTimeGetSeconds(currentTime)
        if finalDuration > 0.1 {
            segments.append(ClipSegment(sourceURL: sourceURL, startTime: currentTime, endTime: duration))
        }

        // 补切长场景
        return refineSegments(segments, targetCount: targetSegmentCount)
    }

    // MARK: - Waste Detection

    /// Detect waste clips (blackout, dark, solid) for a single source file
    private func detectWasteForClips(session: ImportSession, sourceURL: URL, filename: String) async {
        let clipsForSource = session.allClips.filter { $0.sourceFileURL == sourceURL }
        guard !clipsForSource.isEmpty else { return }

        statusMessage = "Detecting waste in \(filename)..."

        let asset = AVAsset(url: sourceURL)
        let wasteResults = await wasteDetector.detectWaste(in: clipsForSource, asset: asset)

        guard !wasteResults.isEmpty else { return }

        // Update wasteType on matching clips
        for i in session.allClips.indices {
            if let wasteType = wasteResults[session.allClips[i].id] {
                session.allClips[i].wasteType = wasteType
            }
        }
    }

    // MARK: - Refinement

    /// 补切长场景片段（流式路径，直接操作 session 中的 VideoClip）
    private func refineLongSegments(
        session: ImportSession,
        targetCount: Int,
        sourceURL: URL,
        totalDuration: Double
    ) {
        let currentClips = session.allClips.filter { $0.sourceFileURL == sourceURL }
        let currentCount = currentClips.count

        guard currentCount < targetCount else { return }

        let budget = targetCount - currentCount
        let idealDuration = totalDuration / Double(targetCount)

        // 找出长片段，按时长降序
        let longClips = currentClips
            .filter { $0.duration > idealDuration }
            .sorted { $0.duration > $1.duration }

        guard !longClips.isEmpty else { return }

        let totalLongDuration = longClips.reduce(0.0) { $0 + $1.duration }

        var replacements: [UUID: [VideoClip]] = [:]
        var remainingBudget = budget

        for longClip in longClips {
            guard remainingBudget > 0 else { break }

            var allocatedSplit: Int
            if longClips.count == 1 {
                allocatedSplit = remainingBudget
            } else {
                allocatedSplit = max(1, Int(round(Double(remainingBudget) * (longClip.duration / totalLongDuration))))
                allocatedSplit = min(allocatedSplit, remainingBudget)
            }

            let partCount = allocatedSplit + 1
            let newClips = splitClipIntoParts(clip: longClip, partCount: partCount)
            replacements[longClip.id] = newClips
            remainingBudget -= allocatedSplit
        }

        // 重建 session clips：保留其他视频的 clips，替换当前视频的长片段
        let otherClips = session.allClips.filter { $0.sourceFileURL != sourceURL }
        let updatedClips = currentClips.flatMap { clip -> [VideoClip] in
            if let replacement = replacements[clip.id] {
                return replacement
            }
            return [clip]
        }

        clipsFoundCount += (updatedClips.count - currentCount)
        session.allClips = otherClips + updatedClips
    }

    /// 将一个 VideoClip 等分为 partCount 段
    private func splitClipIntoParts(clip: VideoClip, partCount: Int) -> [VideoClip] {
        guard partCount > 1 else { return [clip] }

        let partDuration = clip.duration / Double(partCount)
        var clips: [VideoClip] = []

        for i in 0..<partCount {
            let startTime = CMTimeAdd(
                clip.timecodeStart,
                CMTime(seconds: Double(i) * partDuration, preferredTimescale: 600)
            )
            let endTime: CMTime
            if i == partCount - 1 {
                endTime = clip.timecodeEnd
            } else {
                endTime = CMTimeAdd(
                    clip.timecodeStart,
                    CMTime(seconds: Double(i + 1) * partDuration, preferredTimescale: 600)
                )
            }

            let segment = ClipSegment(sourceURL: clip.sourceFileURL, startTime: startTime, endTime: endTime)
            clips.append(segment.toVideoClip())
        }

        return clips
    }

    /// 补切长场景片段（legacy 路径，操作 ClipSegment 数组）
    private func refineSegments(_ segments: [ClipSegment], targetCount: Int) -> [ClipSegment] {
        guard segments.count < targetCount else { return segments }

        let totalDuration = segments.reduce(0.0) {
            $0 + (CMTimeGetSeconds($1.endTime) - CMTimeGetSeconds($1.startTime))
        }
        let budget = targetCount - segments.count
        let idealDuration = totalDuration / Double(targetCount)

        // 找出长片段，按时长降序，保留原始索引
        let longSegments = segments.enumerated()
            .filter { CMTimeGetSeconds($0.element.endTime) - CMTimeGetSeconds($0.element.startTime) > idealDuration }
            .sorted { (CMTimeGetSeconds($0.element.endTime) - CMTimeGetSeconds($0.element.startTime)) > (CMTimeGetSeconds($1.element.endTime) - CMTimeGetSeconds($1.element.startTime)) }

        guard !longSegments.isEmpty else { return segments }

        let totalLongDuration = longSegments.reduce(0.0) {
            $0 + (CMTimeGetSeconds($1.element.endTime) - CMTimeGetSeconds($1.element.startTime))
        }

        var remainingBudget = budget
        var replacementMap: [Int: [ClipSegment]] = [:]

        for (originalIdx, longSeg) in longSegments {
            guard remainingBudget > 0 else { break }

            let segDuration = CMTimeGetSeconds(longSeg.endTime) - CMTimeGetSeconds(longSeg.startTime)
            var allocatedSplit: Int
            if longSegments.count == 1 {
                allocatedSplit = remainingBudget
            } else {
                allocatedSplit = max(1, Int(round(Double(remainingBudget) * (segDuration / totalLongDuration))))
                allocatedSplit = min(allocatedSplit, remainingBudget)
            }

            let partCount = allocatedSplit + 1
            let partDuration = segDuration / Double(partCount)

            var parts: [ClipSegment] = []
            for i in 0..<partCount {
                let startTime = CMTimeAdd(longSeg.startTime, CMTime(seconds: Double(i) * partDuration, preferredTimescale: 600))
                let endTime: CMTime
                if i == partCount - 1 {
                    endTime = longSeg.endTime
                } else {
                    endTime = CMTimeAdd(longSeg.startTime, CMTime(seconds: Double(i + 1) * partDuration, preferredTimescale: 600))
                }
                parts.append(ClipSegment(sourceURL: longSeg.sourceURL, startTime: startTime, endTime: endTime))
            }

            replacementMap[originalIdx] = parts
            remainingBudget -= allocatedSplit
        }

        // 重建片段列表
        var result: [ClipSegment] = []
        for (idx, seg) in segments.enumerated() {
            if let replacement = replacementMap[idx] {
                result.append(contentsOf: replacement)
            } else {
                result.append(seg)
            }
        }

        return result
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
