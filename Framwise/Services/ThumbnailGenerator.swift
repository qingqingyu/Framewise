//
//  ThumbnailGenerator.swift
//  Framwise
//
//  Generates and caches video thumbnails
//

import Foundation
import AVFoundation
import CoreImage
import SwiftUI

actor ThumbnailGenerator {
    // Shared instance for app-wide use
    static let shared = ThumbnailGenerator()

    private var cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 500  // 最多缓存500张缩略图
        return cache
    }()

    private var generators: [URL: AVAssetImageGenerator] = [:]
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Thumbnail Generation

    /// Generate a thumbnail image at the specified time
    func generateThumbnail(
        for url: URL,
        at time: CMTime,
        targetSize: CGSize = CGSize(width: 200, height: 150)
    ) async throws -> CGImage {
        let cacheKey = "\(url.path)_\(CMTimeGetSeconds(time))" as NSString

        // 检查缓存
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // 获取或创建generator
        let generator: AVAssetImageGenerator
        if let existing = generators[url] {
            generator = existing
        } else {
            let asset = AVAsset(url: url)
            generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            generators[url] = generator
        }

        // 生成图像
        let (image, _) = try await generator.image(at: time)

        // 缩放到目标尺寸
        let scaledImage = try scaleImage(image, to: targetSize)

        // 缓存
        cache.setObject(scaledImage, forKey: cacheKey)

        return scaledImage
    }

    /// Generate multiple thumbnails for animation
    func generateThumbnails(
        for clip: VideoClip,
        count: Int = 5,
        targetSize: CGSize = CGSize(width: 200, height: 150)
    ) async throws -> [CGImage] {
        var images: [CGImage] = []
        let duration = clip.duration
        let interval = duration / Double(count + 1)

        for i in 1...count {
            let offset = Double(i) * interval
            let time = CMTimeAdd(clip.timecodeStart, CMTime(seconds: offset, preferredTimescale: 600))

            do {
                let image = try await generateThumbnail(for: clip.sourceFileURL, at: time, targetSize: targetSize)
                images.append(image)
            } catch {
                // 跳过失败的帧
                continue
            }
        }

        // 如果没有生成任何图像，尝试获取第一帧
        if images.isEmpty {
            let firstFrame = try await generateThumbnail(for: clip.sourceFileURL, at: clip.timecodeStart, targetSize: targetSize)
            images.append(firstFrame)
        }

        return images
    }

    // MARK: - Image Processing

    private func scaleImage(_ image: CGImage, to targetSize: CGSize) throws -> CGImage {
        let ciImage = CIImage(cgImage: image)

        // 计算缩放比例（保持宽高比）
        let scaleX = targetSize.width / CGFloat(image.width)
        let scaleY = targetSize.height / CGFloat(image.height)
        let scale = min(scaleX, scaleY)

        let scaledWidth = CGFloat(image.width) * scale
        let scaledHeight = CGFloat(image.height) * scale

        // 缩放
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledCI = ciImage.transformed(by: transform)

        // 裁剪到目标尺寸（居中）
        let cropRect = CGRect(
            x: (scaledWidth - targetSize.width) / 2,
            y: (scaledHeight - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )

        let croppedCI = scaledCI.cropped(to: cropRect)
        guard let outputImage = ciContext.createCGImage(croppedCI, from: cropRect) else {
            throw ThumbnailError.scalingFailed
        }

        return outputImage
    }

    // MARK: - Cache Management

    func clearCache() {
        cache.removeAllObjects()
        generators.removeAll()
    }

    func preloadThumbnails(for clips: [VideoClip], targetSize: CGSize) async {
        await withTaskGroup(of: Void.self) { group in
            for clip in clips {
                for time in clip.thumbnailTimes.prefix(3) {
                    group.addTask {
                        do {
                            _ = try await self.generateThumbnail(
                                for: clip.sourceFileURL,
                                at: time,
                                targetSize: targetSize
                            )
                        } catch {
                            // 忽略预加载错误
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Errors

enum ThumbnailError: LocalizedError {
    case scalingFailed
    case frameExtractionFailed

    var errorDescription: String? {
        switch self {
        case .scalingFailed:
            return "Failed to scale thumbnail image"
        case .frameExtractionFailed:
            return "Failed to extract video frame"
        }
    }
}

// MARK: - SwiftUI Helper

extension CGImage {
    var nsImage: NSImage {
        NSImage(cgImage: self, size: NSSize(width: width, height: height))
    }
}
