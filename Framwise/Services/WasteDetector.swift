//
//  WasteDetector.swift
//  Framwise
//
//  Detects waste clips (blackout, dark, solid, blurry) by sampling frames
//

import Foundation
import AVFoundation
import CoreGraphics

// MARK: - Frame Analysis

private struct FrameAnalysis {
    let meanBrightness: Double
    let brightnessStdDev: Double
    let laplacianVariance: Double
}

actor WasteDetector {

    // MARK: - Thresholds

    /// Blackout: mean brightness < 8/255
    private let blackoutThreshold: Double = 8.0
    /// Dark: mean brightness < 25/255
    private let darkThreshold: Double = 25.0
    /// Solid: brightness std dev < 5/255
    private let solidThreshold: Double = 5.0
    /// Blurry: Laplacian variance below this value indicates out-of-focus content.
    /// Scale is 0–65025 (255^2) for 8-bit grayscale; sharp frames typically >200.
    private let blurryThreshold: Double = 100.0
    /// Minimum votes (out of 3 samples) to mark as waste
    private let requiredVotes: Int = 2

    // MARK: - Public API

    /// Analyze clips and return clip IDs that should be marked as waste
    func detectWaste(in clips: [VideoClip], asset: AVAsset) async -> [UUID: WasteType] {
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            return [:]
        }

        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else { return [:] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        var results: [UUID: WasteType] = [:]

        for clip in clips {
            let clipStart = CMTimeGetSeconds(clip.timecodeStart)
            let clipEnd = CMTimeGetSeconds(clip.timecodeEnd)
            let clipDuration = clipEnd - clipStart

            guard clipDuration > 0.3 else { continue }

            // Sample at 25%, 50%, 75% of clip duration
            let samplePoints = [0.25, 0.50, 0.75]

            var frameAnalyses: [FrameAnalysis] = []

            for ratio in samplePoints {
                let sampleTime = CMTime(
                    seconds: clipStart + clipDuration * ratio,
                    preferredTimescale: 600
                )

                do {
                    let (image, _) = try await generator.image(at: sampleTime)
                    let analysis = analyzeFrame(image)
                    frameAnalyses.append(analysis)
                } catch {
                    // Skip frames that can't be extracted
                    continue
                }
            }

            guard frameAnalyses.count >= 1 else { continue }

            let wasteType = classifyWaste(frames: frameAnalyses)
            if wasteType != .none {
                results[clip.id] = wasteType
            }
        }

        return results
    }

    // MARK: - Frame Analysis

    private func analyzeFrame(_ cgImage: CGImage) -> FrameAnalysis {
        let size = 50
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return FrameAnalysis(meanBrightness: 128, brightnessStdDev: 50, laplacianVariance: 500)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let pixelData = context.data else {
            return FrameAnalysis(meanBrightness: 128, brightnessStdDev: 50, laplacianVariance: 500)
        }

        let pixels = pixelData.assumingMemoryBound(to: UInt8.self)
        let pixelCount = size * size

        // Build grayscale buffer and compute brightness stats in one pass
        var sum: Double = 0
        var grays = [Double](repeating: 0, count: pixelCount)

        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                let gray = Double(pixels[offset]) * 0.299
                           + Double(pixels[offset + 1]) * 0.587
                           + Double(pixels[offset + 2]) * 0.114
                sum += gray
                grays[y * size + x] = gray
            }
        }

        let mean = sum / Double(pixelCount)

        var varianceSum: Double = 0
        for g in grays {
            let diff = g - mean
            varianceSum += diff * diff
        }
        let stdDev = sqrt(varianceSum / Double(pixelCount))

        // Laplacian variance for blur detection.
        // 3x3 kernel: [0,1,0; 1,-4,1; 0,1,0] applied to interior pixels.
        let laplacianVariance = computeLaplacianVariance(grays: grays, size: size)

        return FrameAnalysis(meanBrightness: mean, brightnessStdDev: stdDev, laplacianVariance: laplacianVariance)
    }

    /// Convolve with Laplacian kernel and return variance of the response.
    /// High variance = sharp edges present; low variance = blurry / out-of-focus.
    private func computeLaplacianVariance(grays: [Double], size: Int) -> Double {
        let interiorCount = (size - 2) * (size - 2)
        guard interiorCount > 0 else { return 500 }

        var lapSum: Double = 0
        var lapSqSum: Double = 0

        for y in 1..<(size - 1) {
            for x in 1..<(size - 1) {
                let center = grays[y * size + x]
                let top    = grays[(y - 1) * size + x]
                let bottom = grays[(y + 1) * size + x]
                let left   = grays[y * size + (x - 1)]
                let right  = grays[y * size + (x + 1)]

                let lap = top + bottom + left + right - 4.0 * center
                lapSum += lap
                lapSqSum += lap * lap
            }
        }

        let lapMean = lapSum / Double(interiorCount)
        return (lapSqSum / Double(interiorCount)) - (lapMean * lapMean)
    }

    // MARK: - Classification

    private func classifyFrame(_ frame: FrameAnalysis) -> WasteType {
        // Priority: blackout > dark > solid > blurry
        // Blur check is last because black/dark/solid frames naturally
        // have low Laplacian variance and should not be double-classified.
        if frame.meanBrightness < blackoutThreshold {
            return .blackout
        }
        if frame.meanBrightness < darkThreshold {
            return .dark
        }
        if frame.brightnessStdDev < solidThreshold {
            return .solid
        }
        if frame.laplacianVariance < blurryThreshold {
            return .blurry
        }
        return .none
    }

    /// Majority voting: >=2 of 3 frames must agree on same waste type.
    /// For short clips with only 1 sample, a single unanimous vote suffices.
    private func classifyWaste(frames: [FrameAnalysis]) -> WasteType {
        var votes: [WasteType: Int] = [:]
        for frame in frames {
            let type = classifyFrame(frame)
            if type != .none {
                votes[type, default: 0] += 1
            }
        }

        // Find type with most votes
        if let (type, count) = votes.max(by: { $0.value < $1.value }) {
            // For 1 sample: single vote is enough; for 2-3 samples: need requiredVotes
            let threshold = frames.count == 1 ? 1 : requiredVotes
            if count >= threshold {
                return type
            }
        }
        return .none
    }
}
