//
//  SceneDetector.swift
//  Framwise
//
//  Detects scene changes (cut points) in video using AVFoundation
//

import Foundation
import AVFoundation
import CoreImage
import Accelerate

// MARK: - Scene Event for Streaming

enum SceneEvent: Sendable {
    case sceneChange(CMTime)
    case progress(Double)
    case completed([CMTime])
    case frameSkipped(time: Double, reason: String)
    case error(Error)
}

actor SceneDetector {
    /// Internal detection threshold (0.0 - 1.0). Higher values require larger frame differences.
    var sensitivity: Double = 0.3

    /// Minimum duration between detected cuts (in seconds)
    var minimumSceneDuration: Double = 0.5

    /// Update the internal threshold from the user-facing sensitivity setting.
    func setSensitivity(_ value: Double) {
        sensitivity = SceneDetectionSettings.threshold(forUISensitivity: value)
    }

    // MARK: - Scene Detection

    /// Detect scene change points in a video asset
    func detectScenes(in asset: AVAsset) async throws -> [CMTime] {
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds > 0 else {
            return []
        }

        // 获取视频轨道
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw SceneDetectorError.noVideoTrack
        }

        let frameRate = try await videoTrack.load(.nominalFrameRate)

        // 使用AVAssetImageGenerator获取帧
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // 每秒采样帧数（基于帧率，但限制在合理范围内）
        let samplesPerSecond = min(max(Double(frameRate) / 2, 5), 15)
        let sampleInterval = 1.0 / samplesPerSecond

        var sceneChanges: [CMTime] = []
        var previousHistogram: [Double]?

        var currentTime = 0.0
        var lastSceneTime = 0.0

        while currentTime < durationSeconds {
            let time = CMTime(seconds: currentTime, preferredTimescale: 600)

            do {
                let (image, _) = try await generator.image(at: time)
                let histogram = try computeHistogram(from: image)

                if let prevHist = previousHistogram {
                    let difference = histogramDifference(histogram, prevHist)

                    // 如果差异超过阈值且距离上一个场景足够远
                    if difference > sensitivity && (currentTime - lastSceneTime) >= minimumSceneDuration {
                        sceneChanges.append(time)
                        lastSceneTime = currentTime
                    }
                }

                previousHistogram = histogram
            } catch {
                // Skip frames that cannot be extracted (e.g., corrupted, codec issues)
                // This is expected for some video formats; continue processing
                #if DEBUG
                print("[SceneDetector] Skipped frame at \(currentTime)s: \(error.localizedDescription)")
                #endif
            }

            currentTime += sampleInterval
        }

        // 起点 + 结束点
        return [CMTime.zero] + sceneChanges + [duration]
    }

    /// Duration threshold (seconds) above which two-phase sampling is used.
    private let twoPhaseThreshold: Double = 300 // 5 minutes

    /// Detect scene change points with streaming events.
    /// Short videos (<5 min): single-pass at full sampling rate.
    /// Long videos (>=5 min): two-phase — coarse 1fps scan, then fine scan around change regions.
    func detectScenesStream(in asset: AVAsset) -> AsyncStream<SceneEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let duration = try await asset.load(.duration)
                    let durationSeconds = CMTimeGetSeconds(duration)

                    guard durationSeconds > 0 else {
                        continuation.yield(.completed([]))
                        continuation.finish()
                        return
                    }

                    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                        throw SceneDetectorError.noVideoTrack
                    }

                    let frameRate = try await videoTrack.load(.nominalFrameRate)

                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.requestedTimeToleranceBefore = .zero
                    generator.requestedTimeToleranceAfter = .zero

                    let fineRate = min(max(Double(frameRate) / 2, 5), 15)
                    let fineInterval = 1.0 / fineRate
                    let activeSensitivity = self.sensitivity
                    let activeMinDuration = self.minimumSceneDuration

                    if durationSeconds >= self.twoPhaseThreshold {
                        let result = try await self.twoPhaseDetect(
                            generator: generator,
                            durationSeconds: durationSeconds,
                            fineInterval: fineInterval,
                            sensitivity: activeSensitivity,
                            minSceneDuration: activeMinDuration,
                            continuation: continuation
                        )
                        continuation.yield(.completed([CMTime.zero] + result + [duration]))
                    } else {
                        let result = try await self.singlePassDetect(
                            generator: generator,
                            durationSeconds: durationSeconds,
                            sampleInterval: fineInterval,
                            sensitivity: activeSensitivity,
                            minSceneDuration: activeMinDuration,
                            continuation: continuation
                        )
                        continuation.yield(.completed([CMTime.zero] + result + [duration]))
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Single-Pass Detection (short videos)

    private func singlePassDetect(
        generator: AVAssetImageGenerator,
        durationSeconds: Double,
        sampleInterval: Double,
        sensitivity: Double,
        minSceneDuration: Double,
        continuation: AsyncStream<SceneEvent>.Continuation
    ) async throws -> [CMTime] {
        var sceneChanges: [CMTime] = []
        var previousHistogram: [Double]?
        var currentTime = 0.0
        var lastSceneTime = 0.0

        while currentTime < durationSeconds {
            guard !Task.isCancelled else { throw CancellationError() }

            let time = CMTime(seconds: currentTime, preferredTimescale: 600)
            do {
                let (image, _) = try await generator.image(at: time)
                let histogram = try computeHistogram(from: image)

                if let prevHist = previousHistogram {
                    let difference = histogramDifference(histogram, prevHist)
                    if difference > sensitivity && (currentTime - lastSceneTime) >= minSceneDuration {
                        sceneChanges.append(time)
                        lastSceneTime = currentTime
                        continuation.yield(.sceneChange(time))
                    }
                }
                previousHistogram = histogram
            } catch {
                continuation.yield(.frameSkipped(time: currentTime, reason: error.localizedDescription))
            }

            continuation.yield(.progress(currentTime / durationSeconds))
            currentTime += sampleInterval
        }
        return sceneChanges
    }

    // MARK: - Two-Phase Detection (long videos)

    private func twoPhaseDetect(
        generator: AVAssetImageGenerator,
        durationSeconds: Double,
        fineInterval: Double,
        sensitivity: Double,
        minSceneDuration: Double,
        continuation: AsyncStream<SceneEvent>.Continuation
    ) async throws -> [CMTime] {
        // Phase 1: Coarse scan at 1 sample/sec to find candidate change regions.
        // Uses a lower threshold (70%) to avoid missing changes at low temporal resolution.
        // Enforces minSceneDuration to prevent rapid flicker from creating excessive windows.
        let coarseInterval = 1.0
        let coarseThreshold = sensitivity * 0.7
        var candidateRegions: [Double] = []
        var prevHistogram: [Double]?
        var t = 0.0
        var lastCandidateTime = 0.0

        while t < durationSeconds {
            guard !Task.isCancelled else { throw CancellationError() }
            let time = CMTime(seconds: t, preferredTimescale: 600)

            do {
                let (image, _) = try await generator.image(at: time)
                let histogram = try computeHistogram(from: image)

                if let prev = prevHistogram {
                    let diff = histogramDifference(histogram, prev)
                    if diff > coarseThreshold && (t - lastCandidateTime) >= minSceneDuration {
                        candidateRegions.append(t)
                        lastCandidateTime = t
                    }
                }
                prevHistogram = histogram
            } catch {
                continuation.yield(.frameSkipped(time: t, reason: error.localizedDescription))
            }

            continuation.yield(.progress(t / durationSeconds * 0.5))
            t += coarseInterval
        }

        // Phase 2: Fine scan in ±margin windows around each candidate.
        let margin = max(coarseInterval, 1.0)
        let windows = Self.mergeWindows(
            candidateRegions.map { ($0 - margin, $0 + margin) },
            clampedTo: 0...durationSeconds
        )

        let totalFineTime = max(1.0, windows.reduce(0.0) { $0 + ($1.1 - $1.0) })
        var fineTimeDone = 0.0
        var sceneChanges: [CMTime] = []
        var finePrevHistogram: [Double]?
        var lastSceneTime = 0.0

        for (windowStart, windowEnd) in windows {
            // Sample a frame just before the window to establish baseline histogram
            let baselineTime = max(0, windowStart - fineInterval)
            if finePrevHistogram == nil || windowStart > lastSceneTime + margin * 2 {
                let baseTime = CMTime(seconds: baselineTime, preferredTimescale: 600)
                if let (img, _) = try? await generator.image(at: baseTime),
                   let hist = try? computeHistogram(from: img) {
                    finePrevHistogram = hist
                }
            }

            var ft = windowStart
            while ft < windowEnd {
                guard !Task.isCancelled else { throw CancellationError() }
                let time = CMTime(seconds: ft, preferredTimescale: 600)

                do {
                    let (image, _) = try await generator.image(at: time)
                    let histogram = try computeHistogram(from: image)

                    if let prev = finePrevHistogram {
                        let diff = histogramDifference(histogram, prev)
                        if diff > sensitivity && (ft - lastSceneTime) >= minSceneDuration {
                            sceneChanges.append(time)
                            lastSceneTime = ft
                            continuation.yield(.sceneChange(time))
                        }
                    }
                    finePrevHistogram = histogram
                } catch {
                    continuation.yield(.frameSkipped(time: ft, reason: error.localizedDescription))
                }

                fineTimeDone += fineInterval
                let progress = 0.5 + min(1.0, fineTimeDone / totalFineTime) * 0.5
                continuation.yield(.progress(progress))
                ft += fineInterval
            }
        }

        return sceneChanges
    }

    /// Merge overlapping (start, end) intervals and clamp to the given range.
    private static func mergeWindows(
        _ windows: [(Double, Double)],
        clampedTo range: ClosedRange<Double>
    ) -> [(Double, Double)] {
        guard !windows.isEmpty else { return [] }
        let clamped = windows
            .map { (max(range.lowerBound, $0.0), min(range.upperBound, $0.1)) }
            .filter { $0.0 < $0.1 }
        guard !clamped.isEmpty else { return [] }
        let sorted = clamped.sorted { $0.0 < $1.0 }
        var merged: [(Double, Double)] = [sorted[0]]
        for window in sorted.dropFirst() {
            if window.0 <= merged[merged.count - 1].1 {
                merged[merged.count - 1].1 = max(merged[merged.count - 1].1, window.1)
            } else {
                merged.append(window)
            }
        }
        return merged
    }

    // MARK: - Histogram Computation

    private func computeHistogram(from cgImage: CGImage) throws -> [Double] {
        let width = cgImage.width
        let height = cgImage.height

        // 缩小图片以加速处理
        let scale = min(1.0, 100.0 / Double(min(width, height)))
        let scaledWidth = Int(Double(width) * scale)
        let scaledHeight = Int(Double(height) * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: scaledWidth,
            height: scaledHeight,
            bitsPerComponent: 8,
            bytesPerRow: scaledWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SceneDetectorError.histogramError
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))

        guard let pixelData = context.data else {
            throw SceneDetectorError.histogramError
        }

        let pixels = pixelData.assumingMemoryBound(to: UInt8.self)
        var histogram = [Double](repeating: 0, count: 64)  // 4 bins per channel x 16 bins

        for y in 0..<scaledHeight {
            for x in 0..<scaledWidth {
                let offset = (y * scaledWidth + x) * 4
                let r = Int(pixels[offset]) / 64
                let g = Int(pixels[offset + 1]) / 64
                let b = Int(pixels[offset + 2]) / 64

                let binIndex = r + g * 4 + b * 16
                histogram[binIndex] += 1
            }
        }

        // 归一化
        let totalPixels = Double(scaledWidth * scaledHeight)
        return histogram.map { $0 / totalPixels }
    }

    /// Calculate histogram difference using chi-square distance
    private func histogramDifference(_ h1: [Double], _ h2: [Double]) -> Double {
        guard h1.count == h2.count else { return 1.0 }

        var sum = 0.0
        for i in 0..<h1.count {
            let a = h1[i]
            let b = h2[i]
            if a + b > 0 {
                sum += (a - b) * (a - b) / (a + b)
            }
        }

        return sum / 2.0
    }
}

// MARK: - Errors

enum SceneDetectorError: LocalizedError {
    case noVideoTrack
    case histogramError
    case frameExtractionFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found"
        case .histogramError:
            return "Failed to compute image histogram"
        case .frameExtractionFailed:
            return "Failed to extract video frame"
        }
    }
}
