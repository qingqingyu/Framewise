//
//  SimilarityDetector.swift
//  Framwise
//
//  Detects visually similar clips using perceptual hashing (pHash).
//  Groups repeated takes of the same shot so users can compare and keep the best.
//

import Foundation
import AVFoundation
import CoreGraphics

actor SimilarityDetector {

    // MARK: - Constants

    /// Hamming distance threshold: two hashes within this distance are "similar"
    private let similarityThreshold = 10
    /// DCT input size (resized grayscale frame)
    private let dctSize = 32
    /// Low-frequency block kept from DCT output
    private let hashBlockSize = 8

    // MARK: - Public API

    /// Detect similarity groups among clips from the same source video.
    /// Returns groups of 2+ clips that are visually similar.
    func detectSimilarClips(in clips: [VideoClip], asset: AVAsset) async -> [SimilarityGroup] {
        guard clips.count >= 2 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        // Compute perceptual hashes for each clip (2 sample frames per clip)
        var clipHashes: [(clipID: UUID, hashes: [UInt64], duration: Double)] = []

        for clip in clips {
            let clipStart = CMTimeGetSeconds(clip.timecodeStart)
            let clipEnd = CMTimeGetSeconds(clip.timecodeEnd)
            let clipDuration = clipEnd - clipStart
            guard clipDuration > 0.3 else { continue }

            var hashes: [UInt64] = []
            let sampleRatios: [Double] = clipDuration > 2.0 ? [0.25, 0.75] : [0.5]

            for ratio in sampleRatios {
                let sampleTime = CMTime(
                    seconds: clipStart + clipDuration * ratio,
                    preferredTimescale: 600
                )
                do {
                    let (image, _) = try await generator.image(at: sampleTime)
                    let hash = computePHash(image)
                    hashes.append(hash)
                } catch {
                    continue
                }
            }

            guard !hashes.isEmpty else { continue }
            clipHashes.append((clipID: clip.id, hashes: hashes, duration: clip.duration))
        }

        return groupBySimilarity(clipHashes)
    }

    // MARK: - Perceptual Hash (DCT-based)

    /// Compute a 64-bit perceptual hash from a video frame.
    /// Algorithm: resize to 32x32 grayscale -> DCT -> keep 8x8 low-freq -> median threshold
    private func computePHash(_ cgImage: CGImage) -> UInt64 {
        let size = dctSize
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return 0
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let pixelData = context.data else { return 0 }
        let pixels = pixelData.assumingMemoryBound(to: UInt8.self)

        // Convert to Double array
        var matrix = [Double](repeating: 0, count: size * size)
        for i in 0..<(size * size) {
            matrix[i] = Double(pixels[i])
        }

        // Apply 2D DCT
        let dctResult = dct2D(matrix, size: size)

        // Extract top-left 8x8 block (low frequencies).
        // Use all 64 coefficients (including DC) to fill the full 64-bit hash.
        let block = hashBlockSize
        var lowFreq = [Double]()
        lowFreq.reserveCapacity(block * block)

        for y in 0..<block {
            for x in 0..<block {
                lowFreq.append(dctResult[y * size + x])
            }
        }

        // Compute median
        let sorted = lowFreq.sorted()
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            median = sorted[sorted.count / 2]
        }

        // Generate 64-bit hash: 1 if above median, 0 if below
        var hash: UInt64 = 0
        for (i, val) in lowFreq.prefix(64).enumerated() {
            if val > median {
                hash |= (1 << i)
            }
        }

        return hash
    }

    /// Precomputed cosine table for 32x32 DCT — allocated once per process.
    private static let cosTable32: [Double] = {
        let size = 32
        let n = Double(size)
        var table = [Double](repeating: 0, count: size * size)
        for k in 0..<size {
            for i in 0..<size {
                table[k * size + i] = cos(Double.pi * Double(k) * (2.0 * Double(i) + 1.0) / (2.0 * n))
            }
        }
        return table
    }()

    /// 2D DCT (Type-II) using precomputed cosine table
    private func dct2D(_ input: [Double], size: Int) -> [Double] {
        let cosTable = Self.cosTable32

        // Row-wise 1D DCT
        var temp = [Double](repeating: 0, count: size * size)
        for y in 0..<size {
            for k in 0..<size {
                var sum = 0.0
                for x in 0..<size {
                    sum += input[y * size + x] * cosTable[k * size + x]
                }
                temp[y * size + k] = sum
            }
        }

        // Column-wise 1D DCT
        var result = [Double](repeating: 0, count: size * size)
        for x in 0..<size {
            for k in 0..<size {
                var sum = 0.0
                for y in 0..<size {
                    sum += temp[y * size + x] * cosTable[k * size + y]
                }
                result[k * size + x] = sum
            }
        }

        return result
    }

    // MARK: - Hamming Distance

    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - Union-Find Grouping

    /// Clip count threshold below which exhaustive O(C²) is fast enough.
    private static let lshCutoff = 100

    /// Group clips by pHash similarity using Union-Find.
    /// For small sets (≤100 clips): exhaustive all-pairs comparison.
    /// For large sets: multi-band LSH to reduce comparisons from O(C²) to ~O(C).
    private func groupBySimilarity(
        _ clipHashes: [(clipID: UUID, hashes: [UInt64], duration: Double)]
    ) -> [SimilarityGroup] {
        let count = clipHashes.count
        guard count >= 2 else { return [] }

        // Union-Find
        var parent = Array(0..<count)
        var rank = [Int](repeating: 0, count: count)

        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            if rank[ra] < rank[rb] {
                parent[ra] = rb
            } else if rank[ra] > rank[rb] {
                parent[rb] = ra
            } else {
                parent[rb] = ra
                rank[ra] += 1
            }
        }

        if count <= Self.lshCutoff {
            for i in 0..<count {
                for j in (i + 1)..<count {
                    if areSimilar(clipHashes[i].hashes, clipHashes[j].hashes) {
                        union(i, j)
                    }
                }
            }
        } else {
            // Multi-band LSH: split each 64-bit hash into 8 bands of 8 bits.
            // Two clips sharing an identical band value are candidate pairs.
            // ~90% recall at hamming distance 10; >99% at distance ≤5.
            let bandCount = 8
            var bandTables = [[UInt8: [Int]]](repeating: [:], count: bandCount)

            for (idx, entry) in clipHashes.enumerated() {
                for hash in entry.hashes {
                    for band in 0..<bandCount {
                        let bandValue = UInt8((hash >> (band * 8)) & 0xFF)
                        bandTables[band][bandValue, default: []].append(idx)
                    }
                }
            }

            var seen = Set<UInt64>()
            for table in bandTables {
                for (_, bucket) in table {
                    let unique = Array(Set(bucket))
                    guard unique.count >= 2 else { continue }
                    for i in 0..<unique.count {
                        for j in (i + 1)..<unique.count {
                            let a = min(unique[i], unique[j])
                            let b = max(unique[i], unique[j])
                            let key = UInt64(a) << 32 | UInt64(b)
                            guard seen.insert(key).inserted else { continue }
                            if areSimilar(clipHashes[a].hashes, clipHashes[b].hashes) {
                                union(a, b)
                            }
                        }
                    }
                }
            }
        }

        // Collect groups
        var groups: [Int: [Int]] = [:]
        for i in 0..<count {
            let root = find(i)
            groups[root, default: []].append(i)
        }

        return groups.values.compactMap { indices -> SimilarityGroup? in
            guard indices.count >= 2 else { return nil }

            let groupID = UUID()
            let clipIDs = indices.map { clipHashes[$0].clipID }

            let repIndex = indices.max(by: { clipHashes[$0].duration < clipHashes[$1].duration })!
            let repClipID = clipHashes[repIndex].clipID

            return SimilarityGroup(id: groupID, clipIDs: clipIDs, representativeClipID: repClipID)
        }
    }

    /// Check if two clips are similar by comparing their frame hashes pairwise
    private func areSimilar(_ hashesA: [UInt64], _ hashesB: [UInt64]) -> Bool {
        for a in hashesA {
            for b in hashesB {
                if hammingDistance(a, b) <= similarityThreshold {
                    return true
                }
            }
        }
        return false
    }
}
