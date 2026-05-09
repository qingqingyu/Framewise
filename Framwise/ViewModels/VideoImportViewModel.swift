//
//  VideoImportViewModel.swift
//  Framwise
//
//  Handles video import and scene detection
//

import Foundation
import AVFoundation
import Combine

// MARK: - Parallel Import Types

/// Result of analyzing a single video (used for parallel processing)
struct VideoImportResult {
    let sourceURL: URL
    let clips: [VideoClip]
    let wasteTypes: [UUID: WasteType]  // clipID → wasteType
    let similarityGroups: [SimilarityGroup]
}

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

    /// Each video analysis creates its own detector instances to avoid actor serialization.
    /// Shared instances are only kept for setting sensitivity before spawning tasks.
    private let sharedSceneDetector = SceneDetector()

    /// Maximum number of videos analyzed concurrently to avoid CPU/IO saturation.
    private let maxConcurrentAnalysis = 3

    var singleVideoAnalyzer: (URL, Double, Int) async throws -> VideoImportResult

    init() {
        self.singleVideoAnalyzer = { url, sensitivity, targetSegmentCount in
            try await Self.analyzeSingleVideo(
                url: url,
                sensitivity: sensitivity,
                targetSegmentCount: targetSegmentCount
            )
        }
    }

    /// Monotonic counter to prevent stale TaskGroup completions from overwriting newer import state.
    /// Each import increments this; defer blocks only reset state if their generation is still current.
    private var importGeneration: Int = 0

    /// Handle to the running import Task, so cancelImport can cancel it
    private var importTask: Task<Void, Never>?

    private var targetSegmentCount: Int {
        let count = UserDefaults.standard.integer(forKey: "segmentCount")
        return clamped(count,
                       in: SceneDetectionSettings.minTileCount...SceneDetectionSettings.maxTileCount,
                       default: SceneDetectionSettings.defaultTileCount)
    }

    /// Reset import state (called when session is cleared mid-import)
    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        importGeneration += 1
        isImporting = false
        isAnalyzing = false
        importProgress = 0
        analyzingProgress = 0
        currentVideoName = ""
        clipsFoundCount = 0
        totalFilesCount = 0
        statusMessage = ""
        error = nil
    }

    private func clamped(_ value: Int, in range: ClosedRange<Int>, default defaultValue: Int) -> Int {
        guard value >= range.lowerBound else { return defaultValue }
        return min(value, range.upperBound)
    }

    private func clamped(_ value: Double, in range: ClosedRange<Double>, default defaultValue: Double) -> Double {
        guard value >= range.lowerBound else { return defaultValue }
        return min(value, range.upperBound)
    }

    private func uniqueImportURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    // MARK: - Streaming Import (Parallel)

    /// Start a streaming parallel import. This method is synchronous — it spawns
    /// an internal Task stored in `importTask` so that `cancelImport()` can cancel it.
    func importVideosStreaming(from urls: [URL], into session: ImportSession) {
        guard !isImporting else { return }
        let uniqueURLs = uniqueImportURLs(urls)
        guard !uniqueURLs.isEmpty else { return }

        // Cancel any previously running import Task
        importTask?.cancel()

        importGeneration += 1
        let myGeneration = importGeneration
        isImporting = true
        isAnalyzing = true
        error = nil
        importProgress = 0
        analyzingProgress = 0
        statusMessage = "Importing videos..."
        currentVideoName = ""
        clipsFoundCount = 0
        totalFilesCount = uniqueURLs.count

        importTask = Task {
            defer {
                // Only reset state if no newer import has started
                if importGeneration == myGeneration {
                    importTask = nil
                    isImporting = false
                    isAnalyzing = false
                    importProgress = 1.0
                    analyzingProgress = 1.0
                }
            }

            // Pre-validate all files first (fail fast, no partial state)
            for url in uniqueURLs {
                guard !Task.isCancelled else { return }
                do {
                    try validateVideoFile(url)
                } catch {
                    self.error = error
                    statusMessage = "Error: \(error.localizedDescription)"
                    return
                }
            }
            var insertedSourceURLs = Set<URL>()
            for url in uniqueURLs {
                if session.addSourceFile(url) {
                    insertedSourceURLs.insert(url)
                }
            }

            let urlsToAnalyze = uniqueURLs.filter { insertedSourceURLs.contains($0) }
            guard !urlsToAnalyze.isEmpty else {
                statusMessage = "All files already imported."
                return
            }
            totalFilesCount = urlsToAnalyze.count

            let sensitivity = SceneDetectionSettings.autoSensitivity(forTargetCount: targetSegmentCount)

            let targetCount = self.targetSegmentCount
            let analyzer = self.singleVideoAnalyzer
            let concurrencyLimit = self.maxConcurrentAnalysis

            var completedCount = 0
            var failedCount = 0
            var firstError: Error?

            await withTaskGroup(of: (URL, Result<VideoImportResult, Error>).self) { group in
                var enqueued = 0
                var urlIterator = urlsToAnalyze.makeIterator()

                // Seed the group with up to concurrencyLimit tasks
                while enqueued < concurrencyLimit, let url = urlIterator.next() {
                    enqueued += 1
                    group.addTask {
                        do {
                            let result = try await analyzer(url, sensitivity, targetCount)
                            return (url, .success(result))
                        } catch {
                            return (url, .failure(error))
                        }
                    }
                }

                for await (url, groupResult) in group {
                    guard importGeneration == myGeneration, !Task.isCancelled else {
                        group.cancelAll()
                        // Drain remaining results so completed tasks don't leave
                        // source files without clips in the session.
                        for await (url, remainingResult) in group {
                            switch remainingResult {
                            case .success(let result):
                                mergeResult(result, into: session)
                                completedCount += 1
                            case .failure:
                                failedCount += 1
                                if insertedSourceURLs.contains(url) {
                                    session.removeSourceFile(url)
                                    insertedSourceURLs.remove(url)
                                }
                            }
                        }
                        return
                    }
                    completedCount += 1
                    importProgress = Double(completedCount) / Double(urlsToAnalyze.count)
                    analyzingProgress = importProgress
                    currentVideoName = "Processing \(completedCount)/\(urlsToAnalyze.count) videos..."

                    switch groupResult {
                    case .success(let result):
                        mergeResult(result, into: session)
                    case .failure(let error):
                        failedCount += 1
                        if insertedSourceURLs.contains(url) {
                            session.removeSourceFile(url)
                            insertedSourceURLs.remove(url)
                        }
                        #if DEBUG
                        print("[VideoImport] Failed to analyze video: \(error.localizedDescription)")
                        #endif
                        if firstError == nil {
                            firstError = error
                        }
                    }

                    // Enqueue next video to maintain sliding window
                    if let nextURL = urlIterator.next() {
                        group.addTask {
                            do {
                                let result = try await analyzer(nextURL, sensitivity, targetCount)
                                return (nextURL, .success(result))
                            } catch {
                                return (nextURL, .failure(error))
                            }
                        }
                    }
                }
            }

            guard !Task.isCancelled else { return }

            if let error = firstError, completedCount == failedCount {
                self.error = error
                statusMessage = "Error: \(error.localizedDescription)"
            } else {
                session.isAnalyzed = true
                if failedCount > 0 {
                    statusMessage = "Import complete: \(session.clipCount) clips (\(failedCount) file\(failedCount == 1 ? "" : "s") skipped)"
                } else {
                    statusMessage = "Import complete: \(session.clipCount) clips"
                }
            }
        }
    }

    /// Merge a single video's analysis result into the session (called on @MainActor)
    private func mergeResult(_ result: VideoImportResult, into session: ImportSession) {
        let startIndex = session.allClips.count
        session.addClips(result.clips)
        clipsFoundCount += result.clips.count

        // Apply waste markings only to newly added clips
        let wasteKeys = Set(result.wasteTypes.keys)
        for i in startIndex..<session.allClips.count {
            if wasteKeys.contains(session.allClips[i].id),
               let wasteType = result.wasteTypes[session.allClips[i].id] {
                session.allClips[i].wasteType = wasteType
            }
        }

        // Apply similarity groups
        for group in result.similarityGroups {
            let groupClipIDs = Set(group.clipIDs)
            for i in startIndex..<session.allClips.count {
                if groupClipIDs.contains(session.allClips[i].id) {
                    session.allClips[i].similarityGroupID = group.id
                }
            }
            session.similarityGroups.append(group)
        }
    }

    // MARK: - Single Video Analysis (Non-isolated, for parallel execution)

    /// Analyze a single video independently — each call creates its own detector instances
    /// to avoid actor serialization when multiple videos are processed in parallel.
    nonisolated private static func analyzeSingleVideo(
        url: URL,
        sensitivity: Double,
        targetSegmentCount: Int
    ) async throws -> VideoImportResult {
        let asset = AVAsset(url: url)

        // Load tracks
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SceneDetectorError.noVideoTrack
        }
        let sourceFrameRate = max(Double(try await videoTrack.load(.nominalFrameRate)), 24)

        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)

        // Per-video detector instances — no shared actor contention
        let sceneDetector = SceneDetector()
        let wasteDetector = WasteDetector()
        let similarityDetector = SimilarityDetector()

        await sceneDetector.setSensitivity(sensitivity)

        // Stream scene detection
        let stream = await sceneDetector.detectScenesStream(in: asset)

        var clips: [VideoClip] = []
        var lastProcessedTime: CMTime = .zero

        for await event in stream {
            guard !Task.isCancelled else { throw CancellationError() }
            switch event {
            case .sceneChange(let time):
                let segDuration = CMTimeGetSeconds(time) - CMTimeGetSeconds(lastProcessedTime)
                if segDuration > 0.1 {
                    let segment = ClipSegment(sourceURL: url, sourceFrameRate: sourceFrameRate, startTime: lastProcessedTime, endTime: time)
                    clips.append(segment.toVideoClip())
                }
                lastProcessedTime = time

            case .progress:
                break

            case .frameSkipped(let time, let reason):
                #if DEBUG
                print("[VideoImport] Frame skipped at \(time)s: \(reason)")
                #endif

            case .completed:
                // Process final segment
                let finalDuration = CMTimeGetSeconds(duration) - CMTimeGetSeconds(lastProcessedTime)
                if finalDuration > 0.1 {
                    let segment = ClipSegment(sourceURL: url, sourceFrameRate: sourceFrameRate, startTime: lastProcessedTime, endTime: duration)
                    clips.append(segment.toVideoClip())
                }

                // Refine long clips (pure function)
                clips = refineLongClips(clips, targetCount: targetSegmentCount, totalDuration: totalDuration)

            case .error(let error):
                throw error
            }
        }

        // Waste detection
        let wasteTypes = await detectWasteInClips(clips: clips, sourceURL: url, wasteDetector: wasteDetector)

        // Similarity detection (only non-waste clips are worth grouping)
        let nonWasteClips = clips.filter { wasteTypes[$0.id] == nil }
        let similarityGroups = await detectSimilarClips(clips: nonWasteClips, sourceURL: url, similarityDetector: similarityDetector)

        return VideoImportResult(sourceURL: url, clips: clips, wasteTypes: wasteTypes, similarityGroups: similarityGroups)
    }

    // MARK: - Waste Detection (Non-isolated)

    /// Detect waste for a set of clips from a single video
    nonisolated private static func detectWasteInClips(
        clips: [VideoClip],
        sourceURL: URL,
        wasteDetector: WasteDetector
    ) async -> [UUID: WasteType] {
        guard !clips.isEmpty else { return [:] }
        let asset = AVAsset(url: sourceURL)
        return await wasteDetector.detectWaste(in: clips, asset: asset)
    }

    // MARK: - Similarity Detection (Non-isolated)

    nonisolated private static func detectSimilarClips(
        clips: [VideoClip],
        sourceURL: URL,
        similarityDetector: SimilarityDetector
    ) async -> [SimilarityGroup] {
        guard clips.count >= 2 else { return [] }
        let asset = AVAsset(url: sourceURL)
        return await similarityDetector.detectSimilarClips(in: clips, asset: asset)
    }

    // MARK: - Clip Refinement (Pure)

    /// Minimum clip duration after splitting (seconds)
    /// Prevents micro-clips that have no editing value
    private static let minimumClipDuration: Double = 0.5

    /// Refine long clips by splitting them — pure input/output, no session interaction
    nonisolated private static func refineLongClips(
        _ clips: [VideoClip],
        targetCount: Int,
        totalDuration: Double
    ) -> [VideoClip] {
        // Scale targetCount with video duration to avoid over-splitting short videos
        // A 2s video shouldn't be split into 36 parts (~0.056s each)
        let minimumPartDuration = minimumClipDuration
        let maxPartsFromDuration = max(1, Int(totalDuration / minimumPartDuration))
        let effectiveTarget = min(targetCount, maxPartsFromDuration)

        guard clips.count < effectiveTarget else { return clips }

        let budget = effectiveTarget - clips.count
        let idealDuration = totalDuration / Double(effectiveTarget)

        let longClips = clips
            .filter { $0.duration > idealDuration }
            .sorted { $0.duration > $1.duration }

        guard !longClips.isEmpty else { return clips }

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

            // Cap splits so each part is at least minimumClipDuration
            let maxAllowedSplits = max(1, Int(longClip.duration / minimumPartDuration) - 1)
            allocatedSplit = min(allocatedSplit, maxAllowedSplits)

            let partCount = allocatedSplit + 1
            let newClips = splitClipIntoParts(clip: longClip, partCount: partCount)
            replacements[longClip.id] = newClips
            remainingBudget -= allocatedSplit
        }

        return clips.flatMap { clip -> [VideoClip] in
            if let replacement = replacements[clip.id] {
                return replacement
            }
            return [clip]
        }
    }

    /// Split a VideoClip into equal-duration parts
    nonisolated private static func splitClipIntoParts(clip: VideoClip, partCount: Int) -> [VideoClip] {
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

            let segment = ClipSegment(sourceURL: clip.sourceFileURL, sourceFrameRate: clip.sourceFrameRate, startTime: startTime, endTime: endTime)
            clips.append(segment.toVideoClip())
        }

        return clips
    }

    // MARK: - Legacy Import (保留兼容)

    func importVideos(from urls: [URL], into session: ImportSession) async {
        isImporting = true
        error = nil
        statusMessage = "Importing videos..."

        await sharedSceneDetector.setSensitivity(
            SceneDetectionSettings.autoSensitivity(forTargetCount: targetSegmentCount)
        )

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

    // MARK: - Video Analysis (Legacy)

    private func analyzeVideo(_ url: URL) async throws -> [VideoClip] {
        let asset = AVAsset(url: url)

        // 加载tracks
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SceneDetectorError.noVideoTrack
        }
        let sourceFrameRate = max(Double(try await videoTrack.load(.nominalFrameRate)), 24)

        // 检测场景变化点
        statusMessage = "Detecting scenes in \(url.lastPathComponent)..."
        let sceneChanges = try await sharedSceneDetector.detectScenes(in: asset)

        // 根据场景变化生成clip segments
        let segments = try await generateClipSegments(
            from: asset,
            sceneChanges: sceneChanges,
            sourceURL: url,
            sourceFrameRate: sourceFrameRate
        )

        return segments.map { $0.toVideoClip() }
    }

    /// 根据场景变化生成片段（legacy 路径，使用新逻辑）
    private func generateClipSegments(
        from asset: AVAsset,
        sceneChanges: [CMTime],
        sourceURL: URL,
        sourceFrameRate: Double
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
                segments.append(ClipSegment(sourceURL: sourceURL, sourceFrameRate: sourceFrameRate, startTime: currentTime, endTime: cutPoint))
            }
            currentTime = cutPoint
        }

        // 最后一段
        let finalDuration = CMTimeGetSeconds(duration) - CMTimeGetSeconds(currentTime)
        if finalDuration > 0.1 {
            segments.append(ClipSegment(sourceURL: sourceURL, sourceFrameRate: sourceFrameRate, startTime: currentTime, endTime: duration))
        }

        // 补切长场景
        return refineSegments(segments, targetCount: targetSegmentCount)
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
                parts.append(ClipSegment(sourceURL: longSeg.sourceURL, sourceFrameRate: longSeg.sourceFrameRate, startTime: startTime, endTime: endTime))
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
        let ext = url.pathExtension.lowercased()
        guard FileResolver.supportedVideoExtensions.contains(ext) else {
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
