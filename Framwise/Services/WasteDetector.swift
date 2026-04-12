//
//  WasteDetector.swift
//  Framwise
//
//  Detects waste clips (blackout, dark, solid) by sampling frames
//

import Foundation
import AVFoundation
import CoreGraphics

// MARK: - Frame Analysis

private struct FrameAnalysis {
    let meanBrightness: Double
    let brightnessStdDev: Double
}

actor WasteDetector {

    // MARK: - Thresholds

    /// Blackout: mean brightness < 8/255
    private let blackoutThreshold: Double = 8.0
    /// Dark: mean brightness < 25/255
    private let darkThreshold: Double = 25.0
    /// Solid: brightness std dev < 5/255
    private let solidThreshold: Double = 5.0
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

            guard frameAnalyses.count >= 2 else { continue }

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
            return FrameAnalysis(meanBrightness: 128, brightnessStdDev: 50)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let pixelData = context.data else {
            return FrameAnalysis(meanBrightness: 128, brightnessStdDev: 50)
        }

        let pixels = pixelData.assumingMemoryBound(to: UInt8.self)
        let pixelCount = size * size

        // First pass: compute mean brightness
        var sum: Double = 0
        var brightnesses: [Double] = []
        brightnesses.reserveCapacity(pixelCount)

        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                let gray = Double(pixels[offset]) * 0.299
                           + Double(pixels[offset + 1]) * 0.587
                           + Double(pixels[offset + 2]) * 0.114
                sum += gray
                brightnesses.append(gray)
            }
        }

        let mean = sum / Double(pixelCount)

        // Second pass: compute standard deviation
        var varianceSum: Double = 0
        for b in brightnesses {
            let diff = b - mean
            varianceSum += diff * diff
        }
        let stdDev = sqrt(varianceSum / Double(pixelCount))

        return FrameAnalysis(meanBrightness: mean, brightnessStdDev: stdDev)
    }

    // MARK: - Classification

    private func classifyFrame(_ frame: FrameAnalysis) -> WasteType {
        // Check in priority order: blackout > dark > solid
        if frame.meanBrightness < blackoutThreshold {
            return .blackout
        }
        if frame.meanBrightness < darkThreshold {
            return .dark
        }
        if frame.brightnessStdDev < solidThreshold {
            return .solid
        }
        return .none
    }

    /// Majority voting: 3 frames, >=2 must agree on same waste type
    private func classifyWaste(frames: [FrameAnalysis]) -> WasteType {
        var votes: [WasteType: Int] = [:]
        for frame in frames {
            let type = classifyFrame(frame)
            if type != .none {
                votes[type, default: 0] += 1
            }
        }

        // Find type with most votes
        if let (type, count) = votes.max(by: { $0.value < $1.value }), count >= requiredVotes {
            return type
        }
        return .none
    }
}
