//
//  ThumbnailGenerator.swift
//  Framwise
//
//  Generates and caches video thumbnails (memory + disk)
//

import Foundation
import AVFoundation
import CoreImage
import SwiftUI
import CryptoKit

actor ThumbnailGenerator {
    // Shared instance for app-wide use
    static let shared = ThumbnailGenerator()

    // MARK: - Cache Layers

    private var cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 500
        return cache
    }()

    private var generators: [URL: AVAssetImageGenerator] = [:]
    private var generatorOrder: [URL] = []  // LRU: least-recently-used at front
    private let maxGenerators = 20
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Disk cache config
    private let maxDiskCacheSize: Int64 = 2 * 1024 * 1024 * 1024  // 2GB
    private var lastEvictionCheck: Date = .distantPast

    // MARK: - Disk Cache Paths

    private var diskCacheRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("Framwise/thumbnails", isDirectory: true)
        return cacheDir
    }

    /// Hash a file path to a short directory name
    private func diskCacheFolder(for url: URL) -> String {
        let inputData = Data(url.path.utf8)
        let hash = SHA256.hash(data: inputData)
        return hash.compactMap { String(format: "%02x", $0) }.prefix(16).joined()
    }

    /// Disk cache folder URL for a source video
    private func diskCacheDirectory(for url: URL) -> URL {
        diskCacheRoot.appendingPathComponent(diskCacheFolder(for: url), isDirectory: true)
    }

    // MARK: - Thumbnail Generation

    /// Generate a thumbnail image at the specified time
    func generateThumbnail(
        for url: URL,
        at time: CMTime,
        targetSize: CGSize = CGSize(width: 200, height: 150)
    ) async throws -> CGImage {
        let cacheKey = "\(url.path)_\(CMTimeGetSeconds(time))" as NSString

        // Layer 1: Memory cache
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Layer 2: Disk cache
        if let diskImage = readFromDisk(url: url, time: time) {
            cache.setObject(diskImage, forKey: cacheKey)
            return diskImage
        }

        // Layer 3: Generate from video
        let generator = getOrCreateGenerator(for: url)

        let (image, _) = try await generator.image(at: time)
        let scaledImage = try scaleImage(image, to: targetSize)

        // Save to both caches
        cache.setObject(scaledImage, forKey: cacheKey)
        saveToDisk(scaledImage, url: url, time: time)

        return scaledImage
    }

    /// Generate multiple thumbnails for animation
    func generateThumbnails(
        for clip: VideoClip,
        count: Int = 5,
        targetSize: CGSize = CGSize(width: 200, height: 150)
    ) async throws -> [CGImage] {
        let duration = clip.duration
        let interval = duration / Double(count + 1)
        let times = (1...count).map { i in
            CMTimeAdd(clip.timecodeStart, CMTime(seconds: Double(i) * interval, preferredTimescale: 600))
        }

        do {
            return try await generateImagesBatch(for: clip.sourceFileURL, times: times, targetSize: targetSize)
        } catch {
            // Fallback: try first frame only, return empty if that also fails
            if let fallback = try? await generateThumbnail(for: clip.sourceFileURL, at: clip.timecodeStart, targetSize: targetSize) {
                return [fallback]
            }
            return []
        }
    }

    // MARK: - Batch Extraction

    /// Get or create an AVAssetImageGenerator for a source URL
    private func getOrCreateGenerator(for url: URL) -> AVAssetImageGenerator {
        if let existing = generators[url] {
            // Move to end (most recently used)
            generatorOrder.removeAll { $0 == url }
            generatorOrder.append(url)
            return existing
        }
        // Evict least-recently-used generator if at capacity
        if generators.count >= maxGenerators, let lru = generatorOrder.first {
            generators.removeValue(forKey: lru)
            generatorOrder.removeFirst()
        }
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generators[url] = gen
        generatorOrder.append(url)
        return gen
    }

    /// Batch-extract images at multiple times using AVAssetImageGenerator's native batch API.
    /// Let AVFoundation optimize I/O scheduling across all requested times.
    private func generateImagesBatch(
        for url: URL,
        times: [CMTime],
        targetSize: CGSize
    ) async throws -> [CGImage] {
        let generator = getOrCreateGenerator(for: url)

        // Check which frames are already cached (memory + disk)
        var results: [Int: CGImage] = [:]
        var uncachedIndices: [(index: Int, time: NSValue)] = []

        for (i, time) in times.enumerated() {
            let cacheKey = "\(url.path)_\(CMTimeGetSeconds(time))" as NSString
            if let cached = cache.object(forKey: cacheKey) {
                results[i] = cached
            } else if let diskImage = readFromDisk(url: url, time: time) {
                cache.setObject(diskImage, forKey: cacheKey)
                results[i] = diskImage
            } else {
                uncachedIndices.append((index: i, time: NSValue(time: time)))
            }
        }

        guard !uncachedIndices.isEmpty else {
            return times.indices.map { results[$0]! }
        }

        // Batch extract uncached frames via AVFoundation's native batch API
        // Build a lookup from requested CMTime → array index for out-of-order callback matching
        let timeToIndex: [(time: CMTime, index: Int)] = uncachedIndices.map { entry in
            (time: entry.time.timeValue, index: entry.index)
        }

        let batchImages: [Int: CGImage] = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[Int: CGImage], Error>) in
            var collected: [Int: CGImage] = [:]
            let totalCount = uncachedIndices.count
            var remaining = totalCount
            var firstError: Error?
            var resumed = false

            generator.generateCGImagesAsynchronously(
                forTimes: uncachedIndices.map { $0.time }
            ) { requestedTime, image, _, resultInfo, error in
                // Guard against double-resume (corrupt files can produce duplicate callbacks)
                guard !resumed else { return }

                if let image = image {
                    // Match by requestedTime — AVFoundation does not guarantee callback order
                    if let match = timeToIndex.first(where: {
                        CMTimeCompare($0.time, requestedTime) == 0
                    }) {
                        collected[match.index] = image
                    }
                } else if firstError == nil, let error = error {
                    firstError = error
                } else if firstError == nil {
                    firstError = NSError(
                        domain: AVFoundationErrorDomain,
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to extract frame at \(CMTimeGetSeconds(requestedTime))s"]
                    )
                }

                remaining -= 1
                if remaining == 0 {
                    resumed = true
                    if collected.isEmpty, let error = firstError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: collected)
                    }
                }
            }
        }

        // Scale, cache, and merge results
        for (index, rawImage) in batchImages {
            do {
                let scaled = try scaleImage(rawImage, to: targetSize)
                let time = times[index]
                let cacheKey = "\(url.path)_\(CMTimeGetSeconds(time))" as NSString
                cache.setObject(scaled, forKey: cacheKey)
                saveToDisk(scaled, url: url, time: time)
                results[index] = scaled
            } catch {
                // Skip frames that fail to scale
            }
        }

        // Return images in original time order, filling gaps with available images
        let ordered = times.indices.compactMap { results[$0] }
        return ordered
    }

    // MARK: - Image Processing

    private func scaleImage(_ image: CGImage, to targetSize: CGSize) throws -> CGImage {
        let ciImage = CIImage(cgImage: image)

        let scaleX = targetSize.width / CGFloat(image.width)
        let scaleY = targetSize.height / CGFloat(image.height)
        let scale = min(scaleX, scaleY)

        let scaledWidth = CGFloat(image.width) * scale
        let scaledHeight = CGFloat(image.height) * scale

        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledCI = ciImage.transformed(by: transform)

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

    // MARK: - Disk Cache: Write

    private func saveToDisk(_ image: CGImage, url: URL, time: CMTime) {
        let dir = diskCacheDirectory(for: url)
        let fm = FileManager.default

        // Create directory if needed
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            // Write source file metadata for validity check
            writeMetadata(for: url, to: dir)
        }

        let timeSeconds = CMTimeGetSeconds(time)
        let fileName = "frame_\(String(format: "%.3f", timeSeconds)).png"
        let fileURL = dir.appendingPathComponent(fileName)

        // Skip if already on disk
        if fm.fileExists(atPath: fileURL.path) { return }

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        try? pngData.write(to: fileURL, options: .atomic)

        // Touch directory mtime for LRU
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dir.path)

        // Check cache size cap (rate-limited to once per 60s)
        let now = Date()
        if now.timeIntervalSince(lastEvictionCheck) > 60 {
            lastEvictionCheck = now
            enforceCacheSizeLimit()
        }
    }

    // MARK: - Disk Cache: Read

    private func readFromDisk(url: URL, time: CMTime) -> CGImage? {
        let dir = diskCacheDirectory(for: url)
        let fm = FileManager.default

        guard fm.fileExists(atPath: dir.path) else { return nil }

        // Validate source file hasn't changed
        guard isCacheValid(for: url, in: dir) else {
            // Source file changed, evict stale cache
            try? fm.removeItem(at: dir)
            return nil
        }

        let timeSeconds = CMTimeGetSeconds(time)
        let fileName = "frame_\(String(format: "%.3f", timeSeconds)).png"
        let fileURL = dir.appendingPathComponent(fileName)

        guard fm.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // Touch directory mtime for LRU
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: dir.path)

        return cgImage
    }

    // MARK: - Disk Cache: Validity

    /// Source file metadata for cache invalidation
    private struct SourceMetadata: Codable {
        let modificationDate: Double  // time interval since 1970
        let fileSize: Int64
    }

    private func writeMetadata(for url: URL, to dir: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int64 else { return }

        let meta = SourceMetadata(
            modificationDate: mtime.timeIntervalSince1970,
            fileSize: size
        )
        guard let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: dir.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private func isCacheValid(for url: URL, in dir: URL) -> Bool {
        let fm = FileManager.default
        let metaURL = dir.appendingPathComponent("metadata.json")

        guard let metaJSON = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(SourceMetadata.self, from: metaJSON),
              let attrs = try? fm.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int64 else {
            return false
        }

        return abs(mtime.timeIntervalSince1970 - meta.modificationDate) < 1.0 && size == meta.fileSize
    }

    // MARK: - Disk Cache: Eviction

    private func enforceCacheSizeLimit() {
        let fm = FileManager.default
        let root = diskCacheRoot

        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        // Calculate total size
        var totalSize: Int64 = 0
        var dirs: [(url: URL, size: Int64, mtime: Date)] = []

        for dirURL in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let dirSize = directorySize(at: dirURL)
            totalSize += dirSize

            let mtime = (try? fm.attributesOfItem(atPath: dirURL.path)[.modificationDate] as? Date) ?? Date.distantPast
            dirs.append((url: dirURL, size: dirSize, mtime: mtime))
        }

        // If under cap, done
        guard totalSize > maxDiskCacheSize else { return }

        // Sort by mtime ascending (oldest first) and evict until under cap
        dirs.sort { $0.mtime < $1.mtime }

        for dir in dirs {
            try? fm.removeItem(at: dir.url)
            totalSize -= dir.size
            if totalSize <= maxDiskCacheSize { break }
        }
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0

        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        for case let fileURL as URL in enumerator {
            guard let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    // MARK: - Cache Management

    func clearCache() {
        cache.removeAllObjects()
        generators.removeAll()
        generatorOrder.removeAll()

        // Also clear disk cache
        let fm = FileManager.default
        if fm.fileExists(atPath: diskCacheRoot.path) {
            try? fm.removeItem(at: diskCacheRoot)
        }
    }

    /// Preload thumbnails for a batch of clips (uses all cache layers)
    /// Groups clips by source video and uses batch API per video for I/O efficiency
    func preloadThumbnails(for clips: [VideoClip], targetSize: CGSize) async {
        let grouped = Dictionary(grouping: clips, by: { $0.sourceFileURL })
        await withTaskGroup(of: Void.self) { group in
            for (_, clipsForVideo) in grouped {
                group.addTask {
                    let allTimes = clipsForVideo.flatMap { $0.thumbnailTimes.prefix(3) }
                    do {
                        _ = try await self.generateImagesBatch(
                            for: clipsForVideo[0].sourceFileURL,
                            times: allTimes,
                            targetSize: targetSize
                        )
                    } catch {
                        // Ignore preload errors
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
