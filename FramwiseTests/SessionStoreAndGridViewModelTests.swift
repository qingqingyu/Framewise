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

    private func makeTemporaryVideoURL(named name: String = "source.mov") throws -> URL {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent(name)
        try Data("placeholder".utf8).write(to: url)
        return url
    }

    private func waitForSourceResolutionToFinish(_ viewModel: VideoImportViewModel) async throws {
        for _ in 0..<100 {
            if !viewModel.isResolvingSources {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for source resolution")
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

    func testFileResolver_missingSourceReportsAccessIssue() throws {
        let directory = try makeTemporaryDirectory()
        let missingURL = directory.appendingPathComponent("missing.mov")

        let result = FileResolver.resolveVideoURLs(from: [missingURL])

        XCTAssertTrue(result.videoURLs.isEmpty)
        XCTAssertTrue(result.unsupportedNames.isEmpty)
        XCTAssertEqual(result.accessIssues.count, 1)
        XCTAssertEqual(result.accessIssues.first?.title, "missing.mov")
        XCTAssertEqual(result.accessIssues.first?.kind, .missing)
    }

    func testFileResolver_partialAccessibleAndMissingStillReturnsVideos() throws {
        let videoURL = try makeTemporaryVideoURL(named: "good.mov")
        let missingURL = videoURL.deletingLastPathComponent().appendingPathComponent("missing.mov")

        let result = FileResolver.resolveVideoURLs(from: [videoURL, missingURL])

        XCTAssertEqual(result.videoURLs, [videoURL])
        XCTAssertTrue(result.unsupportedNames.isEmpty)
        XCTAssertEqual(result.accessIssues.count, 1)
        XCTAssertEqual(result.accessIssues.first?.kind, .missing)
    }

    func testFileResolver_doesNotImportVideoNamedDirectoriesFromFolderScan() throws {
        let directory = try makeTemporaryDirectory()
        let videoNamedDirectory = directory.appendingPathComponent("folder.mov", isDirectory: true)
        try FileManager.default.createDirectory(at: videoNamedDirectory, withIntermediateDirectories: true)

        let result = FileResolver.resolveVideoURLs(from: [directory])

        XCTAssertTrue(result.videoURLs.isEmpty)
        XCTAssertTrue(result.unsupportedNames.isEmpty)
        XCTAssertTrue(result.accessIssues.isEmpty)
    }

    func testFileResolver_doesNotImportVideoNamedSymlinkedDirectoriesFromFolderScan() throws {
        let directory = try makeTemporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("target", isDirectory: true)
        let symlinkURL = directory.appendingPathComponent("linked.mov")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetDirectory)

        let result = FileResolver.resolveVideoURLs(from: [directory])

        XCTAssertTrue(result.videoURLs.isEmpty)
        XCTAssertTrue(result.unsupportedNames.isEmpty)
        XCTAssertTrue(result.accessIssues.isEmpty)
    }

    func testImportErrorInaccessibleSourcesDescription_doesNotExposeFullPath() {
        let path = "/Users/editor/Private Footage/client/missing.mov"
        let issue = FileAccessIssue(url: URL(fileURLWithPath: path), kind: .missing)

        let description = ImportError.inaccessibleSources([issue], totalCount: 1).localizedDescription

        XCTAssertTrue(description.contains("missing.mov"))
        XCTAssertFalse(description.contains("/Users/editor"))
        XCTAssertFalse(description.contains("Private Footage"))
        XCTAssertFalse(description.contains("client/"))
    }

    func testFileResolver_capsAccessIssuesButTracksTotalCount() throws {
        let directory = try makeTemporaryDirectory()
        let missingURLs = (0..<60).map { index in
            directory.appendingPathComponent("missing-\(index).mov")
        }

        let result = FileResolver.resolveVideoURLs(from: missingURLs)

        XCTAssertTrue(result.videoURLs.isEmpty)
        XCTAssertEqual(result.accessIssues.count, 50)
        XCTAssertEqual(result.suppressedAccessIssueCount, 10)
        XCTAssertEqual(result.accessIssueCount, 60)

        let description = ImportError.inaccessibleSources(
            result.accessIssues,
            totalCount: result.accessIssueCount
        ).localizedDescription
        XCTAssertTrue(description.contains("60 sources"))
    }

    func testFileResolver_reportsWhenVideoLimitStopsFolderScan() throws {
        let directory = try makeTemporaryDirectory()
        for index in 0..<5001 {
            let url = directory.appendingPathComponent("video-\(index).mov")
            try Data("placeholder".utf8).write(to: url)
        }

        let result = FileResolver.resolveVideoURLs(from: [directory])

        XCTAssertEqual(result.videoURLs.count, 5000)
        XCTAssertTrue(result.didReachVideoLimit)
        XCTAssertEqual(result.accessIssues.count, 1)
        XCTAssertEqual(result.accessIssues.first?.kind, .videoLimitReached)
        XCTAssertEqual(result.accessIssueCount, 1)
    }

    func testFileResolver_keepsVideoLimitWarningVisibleWhenAccessIssuesAreCapped() throws {
        let directory = try makeTemporaryDirectory()
        let missingURLs = (0..<50).map { index in
            directory.appendingPathComponent("missing-\(index).mov")
        }
        for index in 0..<5001 {
            let url = directory.appendingPathComponent("video-\(index).mov")
            try Data("placeholder".utf8).write(to: url)
        }

        let result = FileResolver.resolveVideoURLs(from: missingURLs + [directory])

        XCTAssertEqual(result.videoURLs.count, 5000)
        XCTAssertTrue(result.didReachVideoLimit)
        XCTAssertEqual(result.accessIssues.count, 50)
        XCTAssertEqual(result.accessIssues.last?.kind, .videoLimitReached)
        XCTAssertEqual(result.suppressedAccessIssueCount, 1)
        XCTAssertEqual(result.accessIssueCount, 51)
    }

    func testImportSessionRestore_reportsMissingSourceAndCleansDerivedState() {
        let missingURL = URL(fileURLWithPath: "/tmp/framwise-missing-\(UUID().uuidString).mov")
        let firstClip = VideoClip(
            sourceFileURL: missingURL,
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let secondClip = VideoClip(
            sourceFileURL: missingURL,
            timecodeStart: CMTime(seconds: 1, preferredTimescale: 600),
            timecodeEnd: CMTime(seconds: 2, preferredTimescale: 600)
        )
        let data = SessionStore.SessionData(
            version: SessionStore.currentVersion,
            id: UUID(),
            createdDate: Date(),
            sourceFiles: [missingURL],
            allClips: [firstClip, secondClip],
            isAnalyzed: true,
            userClipOrder: [firstClip.id, secondClip.id],
            tags: [],
            activeTagFilter: nil,
            selectedClipIDs: [],
            similarityGroups: [
                SimilarityGroup(clipIDs: [firstClip.id, secondClip.id], representativeClipID: firstClip.id)
            ]
        )
        let session = ImportSession()

        let report = session.restore(from: data)

        XCTAssertEqual(report.removedSourceCount, 1)
        XCTAssertEqual(report.removedClipCount, 2)
        XCTAssertEqual(report.issues.first?.kind, .missing)
        XCTAssertTrue(session.sourceFiles.isEmpty)
        XCTAssertTrue(session.allClips.isEmpty)
        XCTAssertNil(session.userClipOrder)
        XCTAssertTrue(session.similarityGroups.isEmpty)
    }

    func testAppStateRestoreReportClearsWithSession() throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("session.json")
        let missingURL = directory.appendingPathComponent("missing.mov")
        let clip = VideoClip(
            sourceFileURL: missingURL,
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let data = SessionStore.SessionData(
            version: SessionStore.currentVersion,
            id: UUID(),
            createdDate: Date(),
            sourceFiles: [missingURL],
            allClips: [clip],
            isAnalyzed: true,
            userClipOrder: [clip.id],
            tags: [],
            activeTagFilter: nil,
            selectedClipIDs: [clip.id]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(data).write(to: storeURL, options: .atomic)

        let appState = AppState(store: SessionStore(fileURL: storeURL))

        XCTAssertNotNil(appState.restoreReport)
        XCTAssertEqual(appState.restoreReport?.removedSourceCount, 1)
        XCTAssertTrue(appState.selectedClipIDs.isEmpty)

        XCTAssertTrue(appState.clearSession())
        XCTAssertNil(appState.restoreReport)
    }

    func testAppStateFlushSessionToDiskPersistsImmediatelyWithoutDebounce() throws {
        let sourceURL = try makeTemporaryVideoURL(named: "source.mov")
        let storeURL = sourceURL.deletingLastPathComponent().appendingPathComponent("session.json")
        let store = SessionStore(fileURL: storeURL)
        let appState = AppState(store: store)
        let session = ImportSession()
        let clip = VideoClip(
            sourceFileURL: sourceURL,
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
        )

        session.addSourceFile(sourceURL)
        session.addClip(clip)
        appState.importSession = session
        appState.selectedClipIDs = [clip.id]

        XCTAssertTrue(appState.flushSessionToDisk(reason: "unitTest"))

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.sourceFiles, [sourceURL])
        XCTAssertEqual(loaded.allClips.map(\.id), [clip.id])
        XCTAssertEqual(loaded.selectedClipIDs, [clip.id])
    }

    func testAppStateImportResolvedURLs_clearsRestoreReportWhenImportStarts() async throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("session.json")
        let missingURL = directory.appendingPathComponent("missing.mov")
        let restoredClip = VideoClip(
            sourceFileURL: missingURL,
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let data = SessionStore.SessionData(
            version: SessionStore.currentVersion,
            id: UUID(),
            createdDate: Date(),
            sourceFiles: [missingURL],
            allClips: [restoredClip],
            isAnalyzed: true,
            userClipOrder: [restoredClip.id],
            tags: [],
            activeTagFilter: nil,
            selectedClipIDs: [restoredClip.id]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(data).write(to: storeURL, options: .atomic)
        let appState = AppState(store: SessionStore(fileURL: storeURL))
        let importViewModel = VideoImportViewModel()
        let replacementURL = try makeTemporaryVideoURL(named: "replacement.mov")

        importViewModel.singleVideoAnalyzer = { url, _, _ in
            let clip = VideoClip(
                sourceFileURL: url,
                timecodeStart: .zero,
                timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
            )
            return VideoImportResult(sourceURL: url, clips: [clip], wasteTypes: [:], similarityGroups: [])
        }

        XCTAssertNotNil(appState.restoreReport)

        appState.importResolvedURLs([replacementURL], into: importViewModel)
        XCTAssertTrue(importViewModel.isResolvingSources)
        try await waitForSourceResolutionToFinish(importViewModel)

        XCTAssertNil(appState.restoreReport)
        importViewModel.cancelImport()
    }

    func testAppStateImportResolvedURLs_keepsRestoreReportWhenImportIsBusy() throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("session.json")
        let missingURL = directory.appendingPathComponent("missing.mov")
        let restoredClip = VideoClip(
            sourceFileURL: missingURL,
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let data = SessionStore.SessionData(
            version: SessionStore.currentVersion,
            id: UUID(),
            createdDate: Date(),
            sourceFiles: [missingURL],
            allClips: [restoredClip],
            isAnalyzed: true,
            userClipOrder: [restoredClip.id],
            tags: [],
            activeTagFilter: nil,
            selectedClipIDs: [restoredClip.id]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(data).write(to: storeURL, options: .atomic)
        let appState = AppState(store: SessionStore(fileURL: storeURL))
        let importViewModel = VideoImportViewModel()
        let replacementURL = try makeTemporaryVideoURL(named: "replacement.mov")

        importViewModel.isImporting = true

        appState.importResolvedURLs([replacementURL], into: importViewModel)

        XCTAssertNotNil(appState.restoreReport)
        importViewModel.cancelImport()
    }

    func testClearSessionCancelsSourceResolutionState() throws {
        let videoURL = try makeTemporaryVideoURL(named: "valid.mov")
        let storeURL = videoURL.deletingLastPathComponent().appendingPathComponent("session.json")
        let appState = AppState(store: SessionStore(fileURL: storeURL))
        let importViewModel = VideoImportViewModel()

        appState.importResolvedURLs([videoURL], into: importViewModel)

        XCTAssertTrue(importViewModel.isResolvingSources)
        XCTAssertTrue(appState.clearSession())
        XCTAssertFalse(importViewModel.isResolvingSources)
    }

    func testAppStateImportResolvedURLs_replacesActiveSourceResolutionWithLatestRequest() async throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("session.json")
        let appState = AppState(store: SessionStore(fileURL: storeURL))
        let importViewModel = VideoImportViewModel()
        let firstMissingURL = directory.appendingPathComponent("first.mov")
        let secondMissingURL = directory.appendingPathComponent("second.mov")

        appState.importResolvedURLs([firstMissingURL], into: importViewModel)
        XCTAssertTrue(importViewModel.isResolvingSources)

        appState.importResolvedURLs([secondMissingURL], into: importViewModel)
        XCTAssertTrue(importViewModel.isResolvingSources)
        try await waitForSourceResolutionToFinish(importViewModel)

        XCTAssertEqual(
            importViewModel.error?.localizedDescription,
            "Cannot access \"second.mov\". Source is missing or unavailable. Reconnect the volume or choose it again."
        )
    }

    func testAppStateImportResolvedURLs_preservesTotalPreflightWarningCountWhenCapped() async throws {
        let videoURL = try makeTemporaryVideoURL(named: "valid.mov")
        let storeURL = videoURL.deletingLastPathComponent().appendingPathComponent("session.json")
        let missingURLs = (0..<60).map { index in
            videoURL.deletingLastPathComponent().appendingPathComponent("missing-\(index).mov")
        }
        let appState = AppState(store: SessionStore(fileURL: storeURL))
        let importViewModel = VideoImportViewModel()

        importViewModel.singleVideoAnalyzer = { url, _, _ in
            let clip = VideoClip(
                sourceFileURL: url,
                timecodeStart: .zero,
                timecodeEnd: CMTime(seconds: 1, preferredTimescale: 600)
            )
            return VideoImportResult(sourceURL: url, clips: [clip], wasteTypes: [:], similarityGroups: [])
        }

        appState.importResolvedURLs([videoURL] + missingURLs, into: importViewModel)
        XCTAssertTrue(importViewModel.isResolvingSources)
        try await waitForSourceResolutionToFinish(importViewModel)

        XCTAssertEqual(importViewModel.importWarnings.count, 50)
        XCTAssertEqual(importViewModel.importWarningTotalCount, 60)
        XCTAssertEqual(importViewModel.importWarningDisplayCount, 60)
        importViewModel.cancelImport()
    }

    func testAppStateImportResolvedURLs_preservesPreflightWarningsWhenNoVideosImport() async throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("session.json")
        let appState = AppState(store: SessionStore(fileURL: storeURL))
        let importViewModel = VideoImportViewModel()
        let warning = ImportWarning(
            title: "Dropped item",
            message: "Could not read one dropped item."
        )

        appState.importResolvedURLs([], into: importViewModel, preflightWarnings: [warning])
        XCTAssertTrue(importViewModel.isResolvingSources)
        try await waitForSourceResolutionToFinish(importViewModel)

        XCTAssertEqual(importViewModel.importWarnings.count, 1)
        XCTAssertEqual(importViewModel.importWarningTotalCount, 1)
        XCTAssertEqual(importViewModel.importWarnings.first?.title, "Dropped item")
        XCTAssertNotNil(importViewModel.error)
    }

    func testAppStateImportResolvedURLs_reportsOnlyAccessIssueCountInPrimaryError() async throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("session.json")
        let appState = AppState(store: SessionStore(fileURL: storeURL))
        let importViewModel = VideoImportViewModel()
        let missingURL = directory.appendingPathComponent("missing.mov")
        let providerWarning = ImportWarning(
            title: "Dropped item",
            message: "Could not read one dropped item."
        )

        appState.importResolvedURLs(
            [missingURL],
            into: importViewModel,
            preflightWarnings: [providerWarning]
        )
        XCTAssertTrue(importViewModel.isResolvingSources)
        try await waitForSourceResolutionToFinish(importViewModel)

        XCTAssertEqual(importViewModel.error?.localizedDescription, "Cannot access \"missing.mov\". Source is missing or unavailable. Reconnect the volume or choose it again.")
        XCTAssertEqual(importViewModel.importWarnings.count, 1)
        XCTAssertEqual(importViewModel.importWarningDisplayCount, 1)
    }

    func testDropProviderResolverTreatsMissingURLAsVisibleWarning() async {
        let result = await DropProviderResolver.resolveURLsForTesting(
            surface: "test",
            providerCount: 1
        ) { _ in
            .success(nil)
        }

        XCTAssertTrue(result.urls.isEmpty)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings.first?.title, "Dropped item")
        XCTAssertNotNil(result.allProvidersFailedError)
    }

    func testDropProviderResolverPreservesSuccessfulURLsAndProviderWarnings() async {
        let successfulURL = URL(fileURLWithPath: "/tmp/success.mov")
        let result = await DropProviderResolver.resolveURLsForTesting(
            surface: "test",
            providerCount: 3
        ) { index in
            switch index {
            case 0:
                return .success(successfulURL)
            case 1:
                return .success(nil)
            default:
                return .failure(ImportError.fileSelectionFailed)
            }
        }

        XCTAssertEqual(result.urls, [successfulURL])
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertNil(result.allProvidersFailedError)
    }

    func testAppLoggerPublicErrorSummary_doesNotExposeFilePathOrUserInfo() {
        let path = "/Users/editor/Private Footage/client/reel.mov"
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            userInfo: [
                NSFilePathErrorKey: path,
                NSLocalizedDescriptionKey: "The file at \(path) could not be opened."
            ]
        )

        let summary = AppLogger.publicErrorSummary(error)

        XCTAssertTrue(summary.contains("domain=\(NSCocoaErrorDomain)"))
        XCTAssertTrue(summary.contains("code=\(NSFileReadNoSuchFileError)"))
        XCTAssertTrue(summary.contains("type="))
        XCTAssertFalse(summary.contains(path))
        XCTAssertFalse(summary.contains("/Users/editor"))
        XCTAssertFalse(summary.contains("Private Footage"))
        XCTAssertFalse(summary.contains("reel.mov"))
        XCTAssertFalse(summary.contains("could not be opened"))
    }

    func testAppLoggerFileReferences_doNotExposeFullPaths() {
        let url = URL(fileURLWithPath: "/Users/editor/Private Footage/client/reel.mov")

        let fileReference = AppLogger.fileReference(url)
        let pathReference = AppLogger.pathReference(url.deletingLastPathComponent().path)

        XCTAssertTrue(fileReference.hasPrefix("reel.mov#"))
        XCTAssertTrue(pathReference.hasPrefix("client#"))
        XCTAssertFalse(fileReference.contains("/Users/editor"))
        XCTAssertFalse(pathReference.contains("/Users/editor"))
        XCTAssertFalse(fileReference.contains("Private Footage"))
        XCTAssertFalse(pathReference.contains("Private Footage"))
    }
}
