import XCTest
@testable import Framwise
import AVFoundation

actor ImportInvocationCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

actor ImportAnalyzerGate {
    private var startedCount = 0
    private var startWaiters: [(targetCount: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func waitForAnalyzerStart(targetCount: Int) async {
        guard startedCount < targetCount else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((targetCount, continuation))
        }
    }

    func markStartedAndWaitForRelease() async {
        startedCount += 1
        resumeSatisfiedStartWaiters()

        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func releaseAll() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }

    private func resumeSatisfiedStartWaiters() {
        var remaining: [(targetCount: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in startWaiters {
            if startedCount >= waiter.targetCount {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        startWaiters = remaining
    }
}

@MainActor
final class PreviewAndImportViewModelTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    private func makeTemporaryVideoURL(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("placeholder".utf8))
        return url
    }

    private func waitForImportToFinish(_ viewModel: VideoImportViewModel) async throws {
        for _ in 0..<100 {
            if !viewModel.isImporting {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for import to finish")
    }

    func testPreviewPlay_rewindsWhenPlaybackIsAtClipEnd() {
        let viewModel = PreviewViewModel()
        let clip = VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/tmp/test.mov"),
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 5, preferredTimescale: 600)
        )

        viewModel.player = AVPlayer()
        viewModel.currentClip = clip
        viewModel.duration = 5
        viewModel.currentTime = 5

        viewModel.play()

        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertEqual(viewModel.currentTime, 0, accuracy: 0.001)
    }

    func testPreviewPlayIfCurrent_ignoresStalePlayer() {
        let viewModel = PreviewViewModel()
        let currentPlayer = AVPlayer()
        let stalePlayer = AVPlayer()
        let clip = VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/tmp/test.mov"),
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 5, preferredTimescale: 600)
        )

        viewModel.player = currentPlayer
        viewModel.currentClip = clip
        viewModel.duration = 5

        viewModel.playIfCurrent(stalePlayer)

        XCTAssertFalse(viewModel.isPlaying)
    }

    func testCancelImport_clearsDisplayedImportState() {
        let viewModel = VideoImportViewModel()
        viewModel.isImporting = true
        viewModel.isAnalyzing = true
        viewModel.importProgress = 1
        viewModel.analyzingProgress = 1
        viewModel.currentVideoName = "old.mov"
        viewModel.clipsFoundCount = 42
        viewModel.totalFilesCount = 3
        viewModel.statusMessage = "Done"

        viewModel.cancelImport()

        XCTAssertFalse(viewModel.isImporting)
        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertEqual(viewModel.importProgress, 0, accuracy: 0.001)
        XCTAssertEqual(viewModel.analyzingProgress, 0, accuracy: 0.001)
        XCTAssertEqual(viewModel.currentVideoName, "")
        XCTAssertEqual(viewModel.clipsFoundCount, 0)
        XCTAssertEqual(viewModel.totalFilesCount, 0)
        XCTAssertEqual(viewModel.statusMessage, "")
    }

    func testUnsupportedFormatDescription_formatsExtensionsAndFileNamesCleanly() {
        XCTAssertEqual(
            ImportError.unsupportedFormat("txt").errorDescription,
            "Unsupported format: .txt"
        )
        XCTAssertEqual(
            ImportError.unsupportedFiles(["notes.txt", "archive.zip"]).errorDescription,
            "Unsupported file format: notes.txt, archive.zip"
        )
        XCTAssertEqual(
            ImportError.unsupportedFiles(["README"]).errorDescription,
            "Unsupported file format: README"
        )
    }

    func testVideoClipTimecodeStrings_useSourceFrameRate() {
        let clip = VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/tmp/test.mov"),
            sourceFrameRate: 30,
            timecodeStart: CMTime(value: 45, timescale: 30),
            timecodeEnd: CMTime(value: 75, timescale: 30)
        )

        XCTAssertEqual(clip.timecodeStartString, "00:00:01:15")
        XCTAssertEqual(clip.timecodeEndString, "00:00:02:15")
    }

    func testImportVideosStreaming_removesFailedSourceFilesFromSession() async throws {
        let viewModel = VideoImportViewModel()
        let session = ImportSession()
        let successfulURL = try makeTemporaryVideoURL(named: "good.mov")
        let failingURL = try makeTemporaryVideoURL(named: "bad.mov")

        viewModel.singleVideoAnalyzer = { url, _, _ in
            if url == successfulURL {
                let clip = VideoClip(
                    sourceFileURL: url,
                    timecodeStart: .zero,
                    timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
                )
                return VideoImportResult(sourceURL: url, clips: [clip], wasteTypes: [:], similarityGroups: [])
            }
            throw ImportError.analysisFailed("boom")
        }

        viewModel.importVideosStreaming(from: [successfulURL, failingURL], into: session)
        try await waitForImportToFinish(viewModel)

        XCTAssertEqual(session.sourceFiles, [successfulURL])
        XCTAssertEqual(session.allClips.map(\.sourceFileURL), [successfulURL])
        XCTAssertTrue(viewModel.statusMessage.contains("skipped"))
        XCTAssertEqual(viewModel.importWarnings.count, 1)
        XCTAssertEqual(viewModel.importWarningTotalCount, 1)
        XCTAssertEqual(viewModel.importWarnings.first?.sourceURL, failingURL)
    }

    func testImportVideosStreaming_countsPreflightWarningsInCompletionStatus() async throws {
        let viewModel = VideoImportViewModel()
        let session = ImportSession()
        let successfulURL = try makeTemporaryVideoURL(named: "successful.mov")
        let skippedURL = successfulURL.deletingLastPathComponent().appendingPathComponent("missing.mov")
        let preflightWarning = ImportWarning(accessIssue: FileAccessIssue(url: skippedURL, kind: .missing))

        viewModel.singleVideoAnalyzer = { url, _, _ in
            let clip = VideoClip(
                sourceFileURL: url,
                timecodeStart: .zero,
                timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
            )
            return VideoImportResult(sourceURL: url, clips: [clip], wasteTypes: [:], similarityGroups: [])
        }

        viewModel.importVideosStreaming(
            from: [successfulURL],
            into: session,
            preflightWarnings: [preflightWarning],
            preflightWarningTotalCount: 60
        )
        try await waitForImportToFinish(viewModel)

        XCTAssertEqual(viewModel.importWarnings.count, 1)
        XCTAssertEqual(viewModel.importWarningDisplayCount, 60)
        XCTAssertTrue(viewModel.statusMessage.contains("60 files skipped"))
    }

    func testImportVideosStreaming_clampsPreflightWarningTotalToDisplayedWarnings() async throws {
        let viewModel = VideoImportViewModel()
        let session = ImportSession()
        let successfulURL = try makeTemporaryVideoURL(named: "successful.mov")
        let warningURLs = (0..<2).map { index in
            successfulURL.deletingLastPathComponent().appendingPathComponent("missing-\(index).mov")
        }
        let preflightWarnings = warningURLs.map {
            ImportWarning(accessIssue: FileAccessIssue(url: $0, kind: .missing))
        }

        viewModel.singleVideoAnalyzer = { url, _, _ in
            let clip = VideoClip(
                sourceFileURL: url,
                timecodeStart: .zero,
                timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
            )
            return VideoImportResult(sourceURL: url, clips: [clip], wasteTypes: [:], similarityGroups: [])
        }

        viewModel.importVideosStreaming(
            from: [successfulURL],
            into: session,
            preflightWarnings: preflightWarnings,
            preflightWarningTotalCount: 1
        )
        try await waitForImportToFinish(viewModel)

        XCTAssertEqual(viewModel.importWarningTotalCount, 2)
        XCTAssertTrue(viewModel.statusMessage.contains("2 files skipped"))
    }

    func testImportWarningDisplayCountReflectsManuallyRecordedProviderFailures() {
        let viewModel = VideoImportViewModel()
        viewModel.importWarnings = [
            ImportWarning(title: "Dropped item", message: "Could not read one dropped item."),
            ImportWarning(title: "Dropped item", message: "Could not read one dropped item.")
        ]
        viewModel.importWarningTotalCount = 2

        XCTAssertEqual(viewModel.importWarningDisplayCount, 2)
    }

    func testDroppedItemWarningDoesNotExposeUnderlyingErrorDetails() {
        let path = "/Users/editor/Private Footage/client/reel.mov"
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [
                NSFilePathErrorKey: path,
                NSLocalizedDescriptionKey: "The file at \(path) could not be opened."
            ]
        )

        let warning = ImportWarning.droppedItem(error: error)

        XCTAssertEqual(warning.title, "Dropped item")
        XCTAssertFalse(warning.message.contains(path))
        XCTAssertFalse(warning.message.contains("/Users/editor"))
        XCTAssertFalse(warning.message.contains("Private Footage"))
        XCTAssertFalse(warning.message.contains("could not be opened"))
    }

    func testImportWarningForAnalyzerFailureDoesNotExposeUnderlyingErrorDetails() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mov")
        let path = "/Users/editor/Private Footage/client/source.mov"
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: -11800,
            userInfo: [
                NSFilePathErrorKey: path,
                NSLocalizedDescriptionKey: "Operation failed for \(path)"
            ]
        )

        let warning = ImportWarning(sourceURL: sourceURL, error: error)

        XCTAssertEqual(warning.title, "source.mov")
        XCTAssertFalse(warning.message.contains(path))
        XCTAssertFalse(warning.message.contains("/Users/editor"))
        XCTAssertFalse(warning.message.contains("Private Footage"))
        XCTAssertFalse(warning.message.contains("Operation failed"))
    }

    func testImportErrorDroppedItemsUnreadableDoesNotExposeUnderlyingErrorDetails() {
        let description = ImportError.droppedItemsUnreadable(2).localizedDescription

        XCTAssertTrue(description.contains("2 dropped items"))
        XCTAssertFalse(description.contains("/Users/"))
    }

    func testRecordFileSelectionFailureClearsStaleImportWarnings() {
        let viewModel = VideoImportViewModel()
        viewModel.importWarnings = [
            ImportWarning(title: "Dropped item", message: "Could not read one dropped item.")
        ]
        viewModel.importWarningTotalCount = 4
        viewModel.statusMessage = "Import complete: 2 clips (4 files skipped)"

        viewModel.recordFileSelectionFailure()

        XCTAssertEqual(viewModel.importWarnings.count, 0)
        XCTAssertEqual(viewModel.importWarningTotalCount, 0)
        XCTAssertEqual(viewModel.statusMessage, "")
        XCTAssertEqual(viewModel.error?.localizedDescription, ImportError.fileSelectionFailed.localizedDescription)
    }

    func testRecordFileSelectionFailureIgnoresUserCancellation() {
        let viewModel = VideoImportViewModel()
        viewModel.importWarnings = [
            ImportWarning(title: "Dropped item", message: "Could not read one dropped item.")
        ]
        viewModel.importWarningTotalCount = 4
        viewModel.statusMessage = "Import complete: 2 clips (4 files skipped)"

        let recorded = viewModel.recordFileSelectionFailure(CocoaError(.userCancelled))

        XCTAssertFalse(recorded)
        XCTAssertEqual(viewModel.importWarnings.count, 1)
        XCTAssertEqual(viewModel.importWarningTotalCount, 4)
        XCTAssertEqual(viewModel.statusMessage, "Import complete: 2 clips (4 files skipped)")
        XCTAssertNil(viewModel.error)
    }

    func testImportVideosStreaming_deduplicatesRepeatedSourceURLs() async throws {
        let viewModel = VideoImportViewModel()
        let session = ImportSession()
        let duplicateURL = try makeTemporaryVideoURL(named: "same.mov")
        let counter = ImportInvocationCounter()

        viewModel.singleVideoAnalyzer = { url, _, _ in
            await counter.increment()
            let clip = VideoClip(
                sourceFileURL: url,
                timecodeStart: .zero,
                timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
            )
            return VideoImportResult(sourceURL: url, clips: [clip], wasteTypes: [:], similarityGroups: [])
        }

        viewModel.importVideosStreaming(from: [duplicateURL, duplicateURL], into: session)
        try await waitForImportToFinish(viewModel)

        let invocationCount = await counter.value()
        XCTAssertEqual(invocationCount, 1)
        XCTAssertEqual(session.sourceFiles, [duplicateURL])
        XCTAssertEqual(session.allClips.count, 1)
    }

    func testCancelImport_doesNotMergeLateAnalyzerResults() async throws {
        let viewModel = VideoImportViewModel()
        let session = ImportSession()
        let firstURL = try makeTemporaryVideoURL(named: "first.mov")
        let secondURL = try makeTemporaryVideoURL(named: "second.mov")
        let gate = ImportAnalyzerGate()

        viewModel.singleVideoAnalyzer = { url, _, _ in
            await gate.markStartedAndWaitForRelease()
            let clip = VideoClip(
                sourceFileURL: url,
                timecodeStart: .zero,
                timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
            )
            return VideoImportResult(sourceURL: url, clips: [clip], wasteTypes: [:], similarityGroups: [])
        }

        viewModel.importVideosStreaming(from: [firstURL, secondURL], into: session)
        await gate.waitForAnalyzerStart(targetCount: 2)

        viewModel.cancelImport()
        await gate.releaseAll()
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertTrue(session.sourceFiles.isEmpty)
        XCTAssertTrue(session.allClips.isEmpty)
        XCTAssertEqual(viewModel.clipsFoundCount, 0)
        XCTAssertFalse(viewModel.isImporting)
    }
}
