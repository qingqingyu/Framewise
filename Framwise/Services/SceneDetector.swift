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

    private let debugLogPath = "/Users/TWJ/工作/claude/Framwise/.cursor/debug-4a4501.log"
    private let debugSessionId = "4a4501"

    private func writeDebugLog(
        runId: String = "pre-fix",
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        let payload: [String: Any] = [
            "sessionId": debugSessionId,
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]

        guard
            JSONSerialization.isValidJSONObject(payload),
            let jsonData = try? JSONSerialization.data(withJSONObject: payload),
            let lineData = String(data: jsonData, encoding: .utf8)?
                .appending("\n")
                .data(using: .utf8)
        else {
            return
        }

        let logURL = URL(fileURLWithPath: debugLogPath)
        if FileManager.default.fileExists(atPath: debugLogPath),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: lineData)
        } else {
            try? lineData.write(to: logURL)
        }
    }

    /// Update the internal threshold from the user-facing sensitivity setting.
    func setSensitivity(_ value: Double) {
        // #region agent log
        writeDebugLog(
            hypothesisId: "H2",
            location: "SceneDetector.swift:67",
            message: "Scene detector sensitivity updated",
            data: [
                "sensitivity": value
            ]
        )
        // #endregion
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

    /// Detect scene change points with streaming events
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

                    // 每秒采样帧数
                    let samplesPerSecond = min(max(Double(frameRate) / 2, 5), 15)
                    let sampleInterval = 1.0 / samplesPerSecond
                    let activeSensitivity = sensitivity
                    let activeMinimumSceneDuration = minimumSceneDuration

                    var sceneChanges: [CMTime] = []
                    var previousHistogram: [Double]?
                    var debugComparisonsLogged = 0

                    var currentTime = 0.0
                    var lastSceneTime = 0.0

                    // #region agent log
                    writeDebugLog(
                        hypothesisId: "H3",
                        location: "SceneDetector.swift:163",
                        message: "Streaming scene detection started",
                        data: [
                            "durationSeconds": durationSeconds,
                            "samplesPerSecond": samplesPerSecond,
                            "sampleInterval": sampleInterval,
                            "sensitivity": activeSensitivity,
                            "minimumSceneDuration": activeMinimumSceneDuration
                        ]
                    )
                    // #endregion

                    while currentTime < durationSeconds {
                        // Check for cancellation
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }

                        let time = CMTime(seconds: currentTime, preferredTimescale: 600)

                        do {
                            let (image, _) = try await generator.image(at: time)
                            let histogram = try computeHistogram(from: image)

                            if let prevHist = previousHistogram {
                                let difference = histogramDifference(histogram, prevHist)
                                let passesThreshold = difference > activeSensitivity
                                let meetsMinimumDuration = (currentTime - lastSceneTime) >= activeMinimumSceneDuration

                                if debugComparisonsLogged < 8 {
                                    debugComparisonsLogged += 1
                                    // #region agent log
                                    writeDebugLog(
                                        hypothesisId: "H4",
                                        location: "SceneDetector.swift:187",
                                        message: "Scene comparison evaluated",
                                        data: [
                                            "comparisonIndex": debugComparisonsLogged,
                                            "currentTime": currentTime,
                                            "lastSceneTime": lastSceneTime,
                                            "timeSinceLastScene": currentTime - lastSceneTime,
                                            "difference": difference,
                                            "sensitivity": activeSensitivity,
                                            "passesThreshold": passesThreshold,
                                            "meetsMinimumDuration": meetsMinimumDuration,
                                            "willEmitSceneChange": passesThreshold && meetsMinimumDuration
                                        ]
                                    )
                                    // #endregion
                                }

                                if passesThreshold && meetsMinimumDuration {
                                    sceneChanges.append(time)
                                    lastSceneTime = currentTime
                                    // #region agent log
                                    writeDebugLog(
                                        hypothesisId: "H4",
                                        location: "SceneDetector.swift:206",
                                        message: "Scene change emitted",
                                        data: [
                                            "currentTime": currentTime,
                                            "difference": difference,
                                            "sensitivity": activeSensitivity
                                        ]
                                    )
                                    // #endregion
                                    // Emit scene change event
                                    continuation.yield(.sceneChange(time))
                                }
                            }

                            previousHistogram = histogram
                        } catch {
                            // Log skipped frame for debugging (does not stop processing)
                            continuation.yield(.frameSkipped(time: currentTime, reason: error.localizedDescription))
                        }

                        // Emit progress event
                        let progress = currentTime / durationSeconds
                        continuation.yield(.progress(progress))

                        currentTime += sampleInterval
                    }

                    // Emit completion: start + detected cuts + end
                    continuation.yield(.completed([CMTime.zero] + sceneChanges + [duration]))
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error))
                    continuation.finish()
                }
            }
            // Cancel the task when the stream consumer stops listening
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
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
