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

actor SceneDetector {
    /// Sensitivity threshold for scene detection (0.0 - 1.0)
    var sensitivity: Double = 0.3

    /// Minimum duration between detected cuts (in seconds)
    var minimumSceneDuration: Double = 0.5

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

        var sceneChanges: [CMTime] = [CMTime.zero]  // 从0开始
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
                // 跳过无法获取的帧
            }

            currentTime += sampleInterval
        }

        // 添加结束点
        sceneChanges.append(duration)

        return sceneChanges
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
