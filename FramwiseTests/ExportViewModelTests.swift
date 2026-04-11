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

    func testEDL_ContainsHeader() throws {
        let clips = [makeClip(startSeconds: 0, endSeconds: 5)]
        let edl = try viewModel.generateEDL(from: clips)
        XCTAssertTrue(edl.contains("TITLE: Framwise Export"))
        XCTAssertTrue(edl.contains("FCM: NON-DROP FRAME"))
    }

    func testEDL_ReelNameTruncation() throws {
        let clips = [makeClip(sourceName: "VeryLongFileName.mov", startSeconds: 0, endSeconds: 5)]
        let edl = try viewModel.generateEDL(from: clips)

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

    func testEDL_RecTimeAccumulation() throws {
        // REGRESSION: verify O(1) rec time accumulation (not O(n^2) recalculation)
        let clip1 = makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 10)
        let clip2 = makeClip(sourceName: "b.mov", startSeconds: 0, endSeconds: 5)
        let clip3 = makeClip(sourceName: "c.mov", startSeconds: 0, endSeconds: 3)
        let clips = [clip1, clip2, clip3]

        let edl = try viewModel.generateEDL(from: clips)

        // Rec timecodes: 0→10, 10→15, 15→18
        XCTAssertTrue(edl.contains("00:00:10:00 00:00:15:00"), "Clip 2 rec should be 10→15")
        XCTAssertTrue(edl.contains("00:00:15:00 00:00:18:00"), "Clip 3 rec should be 15→18")
    }

    func testEDL_ClipNameAndPath() throws {
        let clips = [makeClip(sourceName: "myclip.mov", startSeconds: 0, endSeconds: 5)]
        let edl = try viewModel.generateEDL(from: clips)
        XCTAssertTrue(edl.contains("FROM CLIP NAME: myclip.mov"))
        XCTAssertTrue(edl.contains("FROM PATH: /tmp/myclip.mov"))
    }

    // MARK: - C. FCPXML Generation (via buildFCPXMLString with fake durations)

    func testFCPXML_ContainsFormatResource() {
        // REGRESSION: format resource must be present
        let clips = [makeClip(startSeconds: 0, endSeconds: 5)]
        let xml = viewModel.buildFCPXMLString(
            clips: clips,
            assetDurations: [URL(fileURLWithPath: "/tmp/test.mov"): 60.0]
        )
        XCTAssertTrue(xml.contains(#"format id="r1001""#), "FCPXML must contain format resource")
    }

    func testFCPXML_XmlEscapedFilenames() {
        // REGRESSION: filenames with special chars must be escaped
        let clips = [makeClip(sourceName: "Tom&Jerry.mov", startSeconds: 0, endSeconds: 5)]
        let url = URL(fileURLWithPath: "/tmp/Tom&Jerry.mov")
        let xml = viewModel.buildFCPXMLString(clips: clips, assetDurations: [url: 60.0])

        XCTAssertTrue(xml.contains("Tom&amp;Jerry.mov"), "Ampersand in filename must be escaped")
        XCTAssertFalse(xml.contains("Tom&J"), "Raw ampersand should not appear in output")
    }

    func testFCPXML_SequenceDurationMatchesClipSum() {
        let clip1 = makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 10)
        let clip2 = makeClip(sourceName: "a.mov", startSeconds: 20, endSeconds: 30)
        let clips = [clip1, clip2]
        let url = URL(fileURLWithPath: "/tmp/a.mov")

        let xml = viewModel.buildFCPXMLString(clips: clips, assetDurations: [url: 120.0])

        // Total duration = 10 + 10 = 20
        XCTAssertTrue(xml.contains("duration=\"20.0s\""), "Sequence duration should equal sum of clip durations")
    }

    func testFCPXML_TcStartIsZero() {
        let clips = [makeClip(startSeconds: 0, endSeconds: 5)]
        let xml = viewModel.buildFCPXMLString(
            clips: clips,
            assetDurations: [URL(fileURLWithPath: "/tmp/test.mov"): 60.0]
        )
        XCTAssertTrue(xml.contains("tcStart=\"0s\""), "Sequence tcStart should be 0s")
    }

    func testFCPXML_ClipOffsetsAreSequential() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        let clip1 = makeClip(sourceName: "a.mov", startSeconds: 0, endSeconds: 10)
        let clip2 = makeClip(sourceName: "a.mov", startSeconds: 20, endSeconds: 25)
        let clip3 = makeClip(sourceName: "a.mov", startSeconds: 50, endSeconds: 53)
        let clips = [clip1, clip2, clip3]

        let xml = viewModel.buildFCPXMLString(clips: clips, assetDurations: [url: 120.0])

        // Offsets should be 0s, 10s, 15s (10+5)
        XCTAssertTrue(xml.contains("offset=\"0.0s\""), "First clip offset should be 0s")
        XCTAssertTrue(xml.contains("offset=\"10.0s\""), "Second clip offset should be 10s")
        XCTAssertTrue(xml.contains("offset=\"15.0s\""), "Third clip offset should be 15s")
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
