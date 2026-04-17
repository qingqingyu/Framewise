//
//  ExportViewModelTests.swift
//  FramwiseTests
//

import XCTest
@testable import Framwise
import AVFoundation

@MainActor
final class ExportViewModelTests: XCTestCase {

    var viewModel: ExportViewModel!

    override func setUp() {
        viewModel = ExportViewModel()
        viewModel.videoInfoLoader = { url in
            ExportViewModel.SourceVideoInfo(
                url: url,
                duration: 120,
                frameRate: 24,
                width: 1920,
                height: 1080
            )
        }
    }

    override func tearDown() {
        viewModel = nil
    }

    // MARK: - Helpers

    private func makeClip(
        sourceName: String = "test.mov",
        startSeconds: Double,
        endSeconds: Double
    ) -> VideoClip {
        VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/tmp/\(sourceName)"),
            timecodeStart: CMTime(seconds: startSeconds, preferredTimescale: 600),
            timecodeEnd: CMTime(seconds: endSeconds, preferredTimescale: 600)
        )
    }

    // MARK: - A. xmlEscaped

    func testXmlEscaped_Ampersand() {
        XCTAssertEqual(viewModel.xmlEscaped("a&b"), "a&amp;b")
    }

    func testXmlEscaped_LessThan() {
        XCTAssertEqual(viewModel.xmlEscaped("a<b"), "a&lt;b")
    }

    func testXmlEscaped_Quote() {
        XCTAssertEqual(viewModel.xmlEscaped("a\"b"), "a&quot;b")
    }

    func testXmlEscaped_CombinedSpecialChars() {
        let input = "<tag attr=\"value&other\">"
        let expected = "&lt;tag attr=&quot;value&amp;other&quot;&gt;"
        XCTAssertEqual(viewModel.xmlEscaped(input), expected)
    }

    // MARK: - B. EDL Generation

    func testEDL_ContainsHeader() async throws {
        let clips = [makeClip(startSeconds: 0, endSeconds: 5)]
        let edl = try await viewModel.generateEDL(from: clips)
        XCTAssertTrue(edl.contains("TITLE: Framwise Export"))
        XCTAssertTrue(edl.contains("FCM: NON-DROP FRAME"))
    }

    func testEDL_ReelNameTruncation() async throws {
        let clips = [makeClip(sourceName: "VeryLongFileName.mov", startSeconds: 0, endSeconds: 5)]
        let edl = try await viewModel.generateEDL(from: clips)

        // Extract the event line (contains event number + reel name)
        let lines = edl.components(separatedBy: "\n")
        let eventLine = lines.first { $0.hasPrefix("001") }
        XCTAssertNotNil(eventLine)

        // Reel name is truncated to 8 chars: "VeryLong"
        if let line = eventLine {
            let afterPrefix = line.dropFirst(5) // skip "001  "
            let reelName = String(afterPrefix.prefix(8))
            XCTAssertEqual(reelName, "VeryLong", "Reel name should be truncated to 8 characters")
        }
    }

    func testEDL_RecTimeAccumulation() async throws {
        // REGRESSION: verify O(1) rec time accumulation (not O(n^2) recalculation)
        let clip1 = makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 10)
        let clip2 = makeClip(sourceName: "b.mov", startSeconds: 0, endSeconds: 5)
        let clip3 = makeClip(sourceName: "c.mov", startSeconds: 0, endSeconds: 3)
        let clips = [clip1, clip2, clip3]

        let edl = try await viewModel.generateEDL(from: clips)

        // Rec timecodes: 0→10, 10→15, 15→18
        XCTAssertTrue(edl.contains("00:00:10:00 00:00:15:00"), "Clip 2 rec should be 10→15")
        XCTAssertTrue(edl.contains("00:00:15:00 00:00:18:00"), "Clip 3 rec should be 15→18")
    }

    func testEDL_ClipNameAndPath() async throws {
        let clips = [makeClip(sourceName: "myclip.mov", startSeconds: 0, endSeconds: 5)]
        let edl = try await viewModel.generateEDL(from: clips)
        XCTAssertTrue(edl.contains("FROM CLIP NAME: myclip.mov"))
        XCTAssertTrue(edl.contains("FROM PATH: /tmp/myclip.mov"))
    }

    // REGRESSION: Each clip's source timecode must use its own source video's frame rate.
    // The rec (timeline) timecode uses the sequence frame rate (first video).
    // This test verifies the code path loads per-source frame rates via buildFCPXMLString's
    // SourceVideoInfo, since the actual loadVideoInfo would fail on /tmp test files.
    func testEDL_RecTimeWithMultipleSources() async throws {
        // Two clips from different source files — tests that the loop handles multiple frameRateMap entries
        let clip1 = makeClip(sourceName: "camera.mov", startSeconds: 0, endSeconds: 10)
        let clip2 = makeClip(sourceName: "drone.mov", startSeconds: 0, endSeconds: 5)
        let clips = [clip1, clip2]

        let edl = try await viewModel.generateEDL(from: clips)

        // Both source files don't exist on disk, so frameRate falls back to 24.0
        // Rec timecodes should still accumulate correctly: 0→10, 10→15
        XCTAssertTrue(edl.contains("00:00:10:00 00:00:15:00"), "Rec time should accumulate across different sources")
    }

    func testEDL_AllInaccessibleSources_ThrowsInsteadOfReturningEmptyExport() async {
        let clips = [
            makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 5),
            makeClip(sourceName: "b.mov", startSeconds: 10, endSeconds: 15)
        ]
        viewModel.videoInfoLoader = { _ in throw CocoaError(.fileReadNoSuchFile) }

        do {
            _ = try await viewModel.generateEDL(from: clips)
            XCTFail("Expected inaccessible EDL export to throw")
        } catch let error as ExportError {
            XCTAssertEqual(error.errorDescription, "Could not export EDL: metadata could not be read for any selected source files.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEDL_PartiallyInaccessibleSources_WarnsAndExportsAccessibleClips() async throws {
        let clip1 = makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 5)
        let clip2 = makeClip(sourceName: "b.mov", startSeconds: 10, endSeconds: 15)
        viewModel.videoInfoLoader = { url in
            if url.lastPathComponent == "a.mov" {
                return ExportViewModel.SourceVideoInfo(url: url, duration: 60, frameRate: 24, width: 1920, height: 1080)
            }
            throw CocoaError(.fileReadNoSuchFile)
        }

        let edl = try await viewModel.generateEDL(from: [clip1, clip2])

        XCTAssertTrue(edl.contains("FROM CLIP NAME: a.mov"))
        XCTAssertFalse(edl.contains("FROM CLIP NAME: b.mov"))
        XCTAssertEqual(viewModel.warning, "1 clip(s) skipped — source file inaccessible.")
    }

    // MARK: - C. FCPXML Generation (via buildFCPXMLString with fake video info)

    private func makeVideoInfo(
        url: URL,
        duration: Double = 60.0,
        frameRate: Double = 24.0,
        width: Int = 1920,
        height: Int = 1080
    ) -> ExportViewModel.SourceVideoInfo {
        ExportViewModel.SourceVideoInfo(url: url, duration: duration, frameRate: frameRate, width: width, height: height)
    }

    func testFCPXML_ContainsFormatResource() {
        // REGRESSION: format resource must be present with dynamic properties
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clips = [makeClip(startSeconds: 0, endSeconds: 5)]
        let infos = [makeVideoInfo(url: url, frameRate: 25, width: 3840, height: 2160)]
        let xml = viewModel.buildFCPXMLString(clips: clips, videoInfos: infos, frameRate: 25, width: 3840, height: 2160)
        XCTAssertTrue(xml.contains(#"format id="r_fmt""#), "FCPXML must contain format resource")
        XCTAssertTrue(xml.contains("2160p25"), "Format name should reflect actual video resolution and frame rate")
    }

    func testFCPXML_XmlEscapedFilenames() {
        // REGRESSION: filenames with special chars must be escaped
        let clips = [makeClip(sourceName: "Tom&Jerry.mov", startSeconds: 0, endSeconds: 5)]
        let url = URL(fileURLWithPath: "/tmp/Tom&Jerry.mov")
        let infos = [makeVideoInfo(url: url)]
        let xml = viewModel.buildFCPXMLString(clips: clips, videoInfos: infos, frameRate: 24, width: 1920, height: 1080)

        XCTAssertTrue(xml.contains("Tom&amp;Jerry.mov"), "Ampersand in filename must be escaped")
        XCTAssertFalse(xml.contains("Tom&J"), "Raw ampersand should not appear in output")
    }

    func testFCPXML_XmlEscapedApostropheAndQuote() {
        // REGRESSION: wedding filenames with apostrophes and quotes
        let clips = [makeClip(sourceName: "John & Sarah's Wedding.mov", startSeconds: 0, endSeconds: 5)]
        let url = URL(fileURLWithPath: "/tmp/John & Sarah's Wedding.mov")
        let infos = [makeVideoInfo(url: url)]
        let xml = viewModel.buildFCPXMLString(clips: clips, videoInfos: infos, frameRate: 24, width: 1920, height: 1080)

        XCTAssertTrue(xml.contains("John &amp; Sarah&apos;s Wedding.mov"), "Ampersand and apostrophe must be escaped")
        XCTAssertFalse(xml.contains("Sarah's"), "Raw apostrophe should not appear in attribute values")
    }

    func testFCPXML_SequenceDurationMatchesClipSum() {
        let clip1 = makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 10)
        let clip2 = makeClip(sourceName: "a.mov", startSeconds: 20, endSeconds: 30)
        let clips = [clip1, clip2]
        let url = URL(fileURLWithPath: "/tmp/a.mov")
        let infos = [makeVideoInfo(url: url, duration: 120.0)]

        let xml = viewModel.buildFCPXMLString(clips: clips, videoInfos: infos, frameRate: 24, width: 1920, height: 1080)

        // Total duration = 10 + 10 = 20
        XCTAssertTrue(xml.contains("duration=\"20/1s\""), "Sequence duration should equal sum of clip durations")
    }

    func testFCPXML_TcStartIsZero() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clips = [makeClip(startSeconds: 0, endSeconds: 5)]
        let infos = [makeVideoInfo(url: url)]
        let xml = viewModel.buildFCPXMLString(clips: clips, videoInfos: infos, frameRate: 24, width: 1920, height: 1080)
        XCTAssertTrue(xml.contains("tcStart=\"0s\""), "Sequence tcStart should be 0s")
    }

    func testFCPXML_ClipOffsetsAreSequential() {
        let clip1 = makeClip(sourceName: "test.mov", startSeconds: 0, endSeconds: 10)
        let clip2 = makeClip(sourceName: "test.mov", startSeconds: 20, endSeconds: 25)
        let clip3 = makeClip(sourceName: "test.mov", startSeconds: 50, endSeconds: 53)
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clips = [clip1, clip2, clip3]
        let infos = [makeVideoInfo(url: url, duration: 120.0)]

        let xml = viewModel.buildFCPXMLString(clips: clips, videoInfos: infos, frameRate: 24, width: 1920, height: 1080)

        // Offsets should be 0s, 10s, 15s (10+5)
        XCTAssertTrue(xml.contains("offset=\"0/1s\""), "First clip offset should be 0s")
        XCTAssertTrue(xml.contains("offset=\"10/1s\""), "Second clip offset should be 10s")
        XCTAssertTrue(xml.contains("offset=\"15/1s\""), "Third clip offset should be 15s")
    }

    func testFCPXML_TcFormatDropFrame() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clips = [makeClip(startSeconds: 0, endSeconds: 5)]
        let infos = [makeVideoInfo(url: url, frameRate: 29.97)]
        let xml = viewModel.buildFCPXMLString(clips: clips, videoInfos: infos, frameRate: 29.97, width: 1920, height: 1080)
        XCTAssertTrue(xml.contains(#"tcFormat="DF""#), "29.97fps should use drop frame format")
    }

    func testFCPXML_AssetUsesAbsoluteString() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clips = [makeClip(startSeconds: 0, endSeconds: 5)]
        let infos = [makeVideoInfo(url: url)]
        let xml = viewModel.buildFCPXMLString(clips: clips, videoInfos: infos, frameRate: 24, width: 1920, height: 1080)
        XCTAssertTrue(xml.contains("src=\"file:///tmp/test.mov\""), "Asset src should use proper file URL")
    }

    func testFCPXML_AllInaccessibleSources_ThrowsInsteadOfReturningEmptyExport() async {
        let clips = [
            makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 5),
            makeClip(sourceName: "b.mov", startSeconds: 10, endSeconds: 15)
        ]
        viewModel.videoInfoLoader = { _ in throw CocoaError(.fileReadNoSuchFile) }

        do {
            _ = try await viewModel.generateFCPXML(from: clips)
            XCTFail("Expected inaccessible FCPXML export to throw")
        } catch let error as ExportError {
            XCTAssertEqual(error.errorDescription, "Could not export FCPXML: metadata could not be read for any selected source files.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFCPXML_PartiallyInaccessibleSources_WarnsAndExportsAccessibleClips() async throws {
        let clip1 = makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 5)
        let clip2 = makeClip(sourceName: "b.mov", startSeconds: 10, endSeconds: 15)
        viewModel.videoInfoLoader = { url in
            if url.lastPathComponent == "a.mov" {
                return ExportViewModel.SourceVideoInfo(url: url, duration: 60, frameRate: 24, width: 1920, height: 1080)
            }
            throw CocoaError(.fileReadNoSuchFile)
        }

        let xml = try await viewModel.generateFCPXML(from: [clip1, clip2])

        XCTAssertTrue(xml.contains("a.mov"))
        XCTAssertFalse(xml.contains("b.mov"))
        XCTAssertEqual(viewModel.warning, "Could not read metadata for: b.mov. Affected clips will be skipped. 1 clip(s) skipped due to inaccessible source files.")
    }

    // MARK: - D. File Naming

    func testFileName_SingleSource_UsesSourceName() {
        let url = URL(fileURLWithPath: "/tmp/MyVideo.mov")
        let clips = [
            VideoClip(sourceFileURL: url, timecodeStart: .zero, timecodeEnd: CMTime(seconds: 5, preferredTimescale: 600)),
            VideoClip(sourceFileURL: url, timecodeStart: CMTime(seconds: 10, preferredTimescale: 600), timecodeEnd: CMTime(seconds: 15, preferredTimescale: 600))
        ]

        let name = viewModel.generateExportFileName(from: clips, fileExtension: "edl")
        XCTAssertEqual(name, "MyVideo_export.edl")
    }

    func testFileName_MultipleSources_UsesDefaultPrefix() {
        let clips = [
            makeClip(sourceName: "video1.mov", startSeconds: 0, endSeconds: 5),
            makeClip(sourceName: "video2.mov", startSeconds: 0, endSeconds: 5)
        ]

        let name = viewModel.generateExportFileName(from: clips, fileExtension: "edl")
        XCTAssertTrue(name.hasPrefix("Framwise_Export_"), "Multi-source filename should start with Framwise_Export_")
        XCTAssertTrue(name.hasSuffix(".edl"), "Filename should have .edl extension")
    }

    func testFileName_CorrectExtension() {
        let url = URL(fileURLWithPath: "/tmp/MyVideo.mov")
        let clips = [
            VideoClip(sourceFileURL: url, timecodeStart: .zero, timecodeEnd: CMTime(seconds: 5, preferredTimescale: 600))
        ]

        XCTAssertEqual(
            viewModel.generateExportFileName(from: clips, fileExtension: "edl"),
            "MyVideo_export.edl"
        )
        XCTAssertEqual(
            viewModel.generateExportFileName(from: clips, fileExtension: "fcpxml"),
            "MyVideo_export.fcpxml"
        )
    }
}
