import XCTest
@testable import Framwise
import AVFoundation

@MainActor
final class PreviewAndImportViewModelTests: XCTestCase {

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
}
