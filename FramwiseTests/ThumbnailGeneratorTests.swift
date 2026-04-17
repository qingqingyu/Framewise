import XCTest
@testable import Framwise
import AVFoundation
import CoreGraphics

final class ThumbnailGeneratorTests: XCTestCase {
    func testDiskCacheFileName_distinguishesCloseFrameTimes() async {
        let generator = ThumbnailGenerator()
        let targetSize = CGSize(width: 220, height: 150)
        let timeA = CMTime(seconds: 1.2340, preferredTimescale: 10_000)
        let timeB = CMTime(seconds: 1.2344, preferredTimescale: 10_000)

        let fileNameA = await generator.diskCacheFileName(for: timeA, targetSize: targetSize)
        let fileNameB = await generator.diskCacheFileName(for: timeB, targetSize: targetSize)

        XCTAssertNotEqual(fileNameA, fileNameB)
    }

    func testLegacyRoundedTimeStamp_requiresExactMillisecondAlignment() async {
        let generator = ThumbnailGenerator()
        let exactTime = CMTime(seconds: 1.2340, preferredTimescale: 10_000)
        let inexactTime = CMTime(seconds: 1.2344, preferredTimescale: 10_000)

        let exactStamp = await generator.legacyRoundedTimeStamp(for: exactTime)
        let inexactStamp = await generator.legacyRoundedTimeStamp(for: inexactTime)

        XCTAssertEqual(exactStamp, "1.234")
        XCTAssertNil(inexactStamp)
    }
}
