import XCTest
@testable import Framwise
import AVFoundation
import CoreGraphics

final class ThumbnailGeneratorTests: XCTestCase {
    func testDiskCacheFileName_distinguishesCloseFrameTimes() {
        let generator = ThumbnailGenerator()
        let targetSize = CGSize(width: 220, height: 150)
        let timeA = CMTime(seconds: 1.2340, preferredTimescale: 10_000)
        let timeB = CMTime(seconds: 1.2344, preferredTimescale: 10_000)

        let fileNameA = generator.diskCacheFileName(for: timeA, targetSize: targetSize)
        let fileNameB = generator.diskCacheFileName(for: timeB, targetSize: targetSize)

        XCTAssertNotEqual(fileNameA, fileNameB)
    }

    func testLegacyRoundedTimeStamp_requiresExactMillisecondAlignment() {
        let generator = ThumbnailGenerator()
        let exactTime = CMTime(seconds: 1.2340, preferredTimescale: 10_000)
        let inexactTime = CMTime(seconds: 1.2344, preferredTimescale: 10_000)

        let exactStamp = generator.legacyRoundedTimeStamp(for: exactTime)
        let inexactStamp = generator.legacyRoundedTimeStamp(for: inexactTime)

        XCTAssertEqual(exactStamp, "1.234")
        XCTAssertNil(inexactStamp)
    }

    func testGenerateThumbnails_rethrowsCancellationWithoutFallback() async {
        let generator = ThumbnailGenerator()
        let clip = VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/tmp/framwise-missing-\(UUID().uuidString).mov"),
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
        )

        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await generator.generateThumbnails(
                for: clip,
                count: 1,
                targetSize: CGSize(width: 40, height: 40)
            )
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected thumbnail generation cancellation to be rethrown.")
        } catch {
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
    }

    func testGenerateThumbnails_returnsEmptyForNonPositiveCount() async throws {
        let generator = ThumbnailGenerator()
        let clip = VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/tmp/framwise-missing-\(UUID().uuidString).mov"),
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
        )

        let images = try await generator.generateThumbnails(
            for: clip,
            count: 0,
            targetSize: CGSize(width: 40, height: 40)
        )

        XCTAssertTrue(images.isEmpty)
    }
}
