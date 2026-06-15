//
//  FramwiseApp.swift
//  Framwise
//
//  Video clip browser and filter tool for editors
//

import SwiftUI
import Combine
import AppKit

@main
struct FramwiseApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SceneDetectionSettings.migrateStoredSensitivityIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1120, minHeight: 760)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .inactive || phase == .background {
                        appState.flushSessionToDisk(reason: "\(phase)")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    appState.flushSessionToDisk(reason: "willTerminate")
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Videos...") {
                    NotificationCenter.default.post(name: .importRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
                Button("Export Selected Clips...") {
                    NotificationCenter.default.post(name: .exportRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .frame(width: 480, height: 360)
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var importSession: ImportSession? {
        didSet {
            normalizeStateForCurrentSession()
            subscribeToSessionChanges()
        }
    }
    @Published var selectedClipIDs: Set<UUID> = []
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0
    @Published var persistenceError: Error?
    @Published var restoreReport: RestoreReport?

    // Source file filtering
    @Published var selectedSourceURL: URL?  // nil = show all

    // Video preview
    @Published var previewClip: VideoClip?

    private let store: SessionStore
    private var cancellables = Set<AnyCancellable>()
    private var fileResolutionTask: Task<Void, Never>?
    private var fileResolutionGeneration = 0
    private weak var activeResolutionImportViewModel: VideoImportViewModel?

    /// Selected clips in the user's arranged order (respects drag-reorder)
    var selectedClips: [VideoClip] {
        guard let session = importSession else { return [] }
        let selected = session.allClips.filter { selectedClipIDs.contains($0.id) }
        guard let order = session.userClipOrder else { return selected }
        let clipMap = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        return order.compactMap { clipMap[$0] }
    }

    convenience init() {
        self.init(store: SessionStore())
    }

    init(store: SessionStore) {
        self.store = store
        // Restore persisted session on startup
        let start = Date()
        do {
            guard let data = try store.load() else {
                AppLogger.info(AppLogger.persistence, "No persisted session found", context: [
                    "durationMs": AppLogger.durationMilliseconds(since: start)
                ])
                return
            }
            let session = ImportSession()
            let report = session.restore(from: data)
            self.importSession = session
            self.restoreReport = report.hasIssues ? report : nil
            // Filter out IDs that no longer correspond to existing clips
            let validIDs = Set(session.allClips.map { $0.id })
            self.selectedClipIDs = data.selectedClipIDs.intersection(validIDs)
            normalizeStateForCurrentSession()
            subscribeToSessionChanges()
            persistenceError = nil
            AppLogger.info(AppLogger.persistence, "Restored persisted session", context: [
                "sessionID": data.id.uuidString,
                "sourceCount": data.sourceFiles.count,
                "clipCount": data.allClips.count,
                "removedSourceCount": report.removedSourceCount,
                "removedClipCount": report.removedClipCount,
                "selectedCount": selectedClipIDs.count,
                "durationMs": AppLogger.durationMilliseconds(since: start)
            ])
        } catch {
            persistenceError = error
            AppLogger.error(AppLogger.persistence, "Failed to restore persisted session", error: error, context: [
                "durationMs": AppLogger.durationMilliseconds(since: start)
            ])
        }
    }

    /// Update preview when selection changes
    func updatePreviewFromSelection() {
        // Only auto-preview when exactly one clip is selected
        if selectedClipIDs.count == 1, let session = importSession {
            if let clipID = selectedClipIDs.first,
               let clip = session.allClips.first(where: { $0.id == clipID }) {
                previewClip = clip
            }
        } else if selectedClipIDs.isEmpty {
            previewClip = nil
        }
    }

    /// Ensure an import session exists, creating one with wedding preset if needed
    func ensureSession() {
        if importSession == nil {
            let session = ImportSession()
            session.loadWeddingPreset()
            importSession = session
            restoreReport = nil
        }
    }

    /// Resolve URLs and import valid videos, or set appropriate error on the import view model.
    func importResolvedURLs(
        _ urls: [URL],
        into importViewModel: VideoImportViewModel,
        preflightWarnings: [ImportWarning] = []
    ) {
        guard !importViewModel.isImporting else { return }

        if fileResolutionTask != nil || importViewModel.isResolvingSources {
            cancelSourceResolution()
        }

        fileResolutionGeneration += 1
        let generation = fileResolutionGeneration
        activeResolutionImportViewModel = importViewModel

        importViewModel.error = nil
        importViewModel.importWarnings = preflightWarnings
        importViewModel.importWarningTotalCount = preflightWarnings.count
        importViewModel.statusMessage = "Reading sources..."
        importViewModel.isResolvingSources = true

        AppLogger.info(AppLogger.fileResolution, "Source resolution started", context: [
            "generation": generation,
            "inputCount": urls.count,
            "preflightWarningCount": preflightWarnings.count
        ])

        fileResolutionTask = Task { [weak self, weak importViewModel] in
            let start = Date()
            let result = await FileResolver.resolveVideoURLsInBackground(from: urls)
            guard let self, let importViewModel else { return }
            guard !Task.isCancelled, generation == self.fileResolutionGeneration else { return }

            self.fileResolutionTask = nil
            self.activeResolutionImportViewModel = nil
            importViewModel.isResolvingSources = false

            AppLogger.info(AppLogger.fileResolution, "Source resolution finished", context: [
                "generation": generation,
                "inputCount": urls.count,
                "videoCount": result.videoURLs.count,
                "unsupportedCount": result.unsupportedNames.count,
                "accessIssueCount": result.accessIssueCount,
                "didReachVideoLimit": result.didReachVideoLimit,
                "durationMs": AppLogger.durationMilliseconds(since: start)
            ])

            self.handleResolvedVideoURLs(
                result,
                into: importViewModel,
                preflightWarnings: preflightWarnings
            )
        }
    }

    private func handleResolvedVideoURLs(
        _ result: FileResolver.ResolveResult,
        into importViewModel: VideoImportViewModel,
        preflightWarnings: [ImportWarning]
    ) {
        if !result.videoURLs.isEmpty {
            ensureSession()
            guard let session = importSession else {
                importViewModel.error = ImportError.noSupportedVideos
                return
            }
            restoreReport = nil
            let warnings = preflightWarnings + result.accessIssues.map(ImportWarning.init(accessIssue:))
            importViewModel.importVideosStreaming(
                from: result.videoURLs,
                into: session,
                preflightWarnings: warnings,
                preflightWarningTotalCount: preflightWarnings.count + result.accessIssueCount
            )
        } else if result.accessIssueCount > 0 {
            importViewModel.error = ImportError.inaccessibleSources(
                result.accessIssues,
                totalCount: result.accessIssueCount
            )
            importViewModel.importWarnings = preflightWarnings
            importViewModel.importWarningTotalCount = preflightWarnings.count
        } else if !result.unsupportedNames.isEmpty {
            importViewModel.error = ImportError.unsupportedFiles(result.unsupportedNames)
            importViewModel.importWarnings = preflightWarnings
            importViewModel.importWarningTotalCount = preflightWarnings.count
        } else {
            importViewModel.error = ImportError.noSupportedVideos
            importViewModel.importWarnings = preflightWarnings
            importViewModel.importWarningTotalCount = preflightWarnings.count
        }
    }

    private func cancelSourceResolution() {
        fileResolutionGeneration += 1
        fileResolutionTask?.cancel()
        fileResolutionTask = nil
        activeResolutionImportViewModel?.isResolvingSources = false
        activeResolutionImportViewModel?.statusMessage = ""
        activeResolutionImportViewModel = nil
    }

    @discardableResult
    func clearSession() -> Bool {
        let previousSessionID = importSession?.id.uuidString ?? "none"
        let previousClipCount = importSession?.clipCount ?? 0
        cancelSourceResolution()
        do {
            try store.delete()
            importSession = nil
            selectedClipIDs = []
            selectedSourceURL = nil
            previewClip = nil
            persistenceError = nil
            restoreReport = nil
            AppLogger.info(AppLogger.persistence, "Cleared persisted session", context: [
                "sessionID": previousSessionID,
                "clipCount": previousClipCount
            ])
            return true
        } catch {
            persistenceError = error
            AppLogger.error(AppLogger.persistence, "Failed to clear persisted session", error: error, context: [
                "sessionID": previousSessionID,
                "clipCount": previousClipCount
            ])
            return false
        }
    }

    // MARK: - Auto-save

    private func subscribeToSessionChanges() {
        cancellables.removeAll()

        // Save when session object changes (debounced)
        if let session = importSession {
            session.objectWillChange
                .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
                .sink { [weak self] in
                    self?.saveToDisk(reason: "sessionChanged")
                }
                .store(in: &cancellables)
        }

        // Save when selection changes (debounced)
        $selectedClipIDs
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveToDisk(reason: "selectionChanged")
            }
            .store(in: &cancellables)
    }

    private func normalizeStateForCurrentSession() {
        guard let session = importSession else {
            selectedSourceURL = nil
            previewClip = nil
            return
        }

        if let selectedSourceURL, !session.sourceFiles.contains(selectedSourceURL) {
            self.selectedSourceURL = nil
        }

        if let previewClip, !session.allClips.contains(where: { $0.id == previewClip.id }) {
            self.previewClip = nil
        }
    }

    @discardableResult
    func flushSessionToDisk(reason: String = "manual") -> Bool {
        saveToDisk(reason: reason)
    }

    @discardableResult
    private func saveToDisk(reason: String) -> Bool {
        guard let session = importSession else { return true }
        let start = Date()
        do {
            try store.save(session: session, selectedClipIDs: selectedClipIDs)
            persistenceError = nil
            AppLogger.info(AppLogger.persistence, "Saved session", context: [
                "sessionID": session.id.uuidString,
                "sourceCount": session.sourceFiles.count,
                "clipCount": session.clipCount,
                "selectedCount": selectedClipIDs.count,
                "reason": reason,
                "durationMs": AppLogger.durationMilliseconds(since: start)
            ])
            return true
        } catch {
            persistenceError = error
            AppLogger.error(AppLogger.persistence, "Failed to save session", error: error, context: [
                "sessionID": session.id.uuidString,
                "sourceCount": session.sourceFiles.count,
                "clipCount": session.clipCount,
                "selectedCount": selectedClipIDs.count,
                "reason": reason,
                "durationMs": AppLogger.durationMilliseconds(since: start)
            ])
            return false
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let exportRequested = Notification.Name("exportRequested")
    static let importRequested = Notification.Name("importRequested")
}
