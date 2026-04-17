import XCTest
@testable import Framwise
import AVFoundation

@MainActor
final class SessionStoreAndGridViewModelTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    func testSessionStoreLoad_migrationPreservesSourceFileMetadata() throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("session.json")
        let store = SessionStore(fileURL: storeURL)
        let sourceURL = directory.appendingPathComponent("source.mov")
        let clip = VideoClip(
            sourceFileURL: sourceURL,
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let metadata = SessionStore.FileMetadata(modificationDate: 1234, fileSize: 5678)
        let sessionData = SessionStore.SessionData(
            version: 1,
            id: UUID(),
            createdDate: Date(),
            sourceFiles: [sourceURL],
            allClips: [clip],
            isAnalyzed: true,
            userClipOrder: nil,
            tags: [],
            activeTagFilter: nil,
            selectedClipIDs: [],
            sourceFileMetadata: [sourceURL: metadata]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sessionData).write(to: storeURL, options: .atomic)

        let loaded = try XCTUnwrap(store.load())

        XCTAssertEqual(loaded.sourceFileMetadata[sourceURL]?.modificationDate, metadata.modificationDate)
        XCTAssertEqual(loaded.sourceFileMetadata[sourceURL]?.fileSize, metadata.fileSize)
    }

    func testClipGridViewModel_resetTransientUIState_restoresDefaults() {
        let viewModel = ClipGridViewModel()

        viewModel.searchText = "wedding"
        viewModel.sortOrder = .duration
        viewModel.viewMode = .selected

        viewModel.resetTransientUIState()

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.sortOrder, .original)
        XCTAssertEqual(viewModel.viewMode, .all)
    }
}
