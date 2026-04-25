//
//  FramwiseApp.swift
//  Framwise
//
//  Video clip browser and filter tool for editors
//

import SwiftUI
import Combine

@main
struct FramwiseApp: App {
    @StateObject private var appState = AppState()

    init() {
        SceneDetectionSettings.migrateStoredSensitivityIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1120, minHeight: 760)
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

    // Source file filtering
    @Published var selectedSourceURL: URL?  // nil = show all

    // Video preview
    @Published var previewClip: VideoClip?

    private let store = SessionStore()
    private var cancellables = Set<AnyCancellable>()

    /// Selected clips in the user's arranged order (respects drag-reorder)
    var selectedClips: [VideoClip] {
        guard let session = importSession else { return [] }
        let selected = session.allClips.filter { selectedClipIDs.contains($0.id) }
        guard let order = session.userClipOrder else { return selected }
        let clipMap = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        return order.compactMap { clipMap[$0] }
    }

    init() {
        // Restore persisted session on startup
        if let data = try? store.load() {
            let session = ImportSession()
            session.restore(from: data)
            self.importSession = session
            // Filter out IDs that no longer correspond to existing clips
            let validIDs = Set(session.allClips.map { $0.id })
            self.selectedClipIDs = data.selectedClipIDs.intersection(validIDs)
            normalizeStateForCurrentSession()
            subscribeToSessionChanges()
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
        }
    }

    func clearSession() {
        importSession = nil
        selectedClipIDs = []
        selectedSourceURL = nil
        previewClip = nil
        store.delete()
    }

    // MARK: - Auto-save

    private func subscribeToSessionChanges() {
        cancellables.removeAll()

        // Save when session object changes (debounced)
        if let session = importSession {
            session.objectWillChange
                .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
                .sink { [weak self] in
                    self?.saveToDisk()
                }
                .store(in: &cancellables)
        }

        // Save when selection changes (debounced)
        $selectedClipIDs
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveToDisk()
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

    private func saveToDisk() {
        guard let session = importSession else { return }
        do {
            try store.save(session: session, selectedClipIDs: selectedClipIDs)
        } catch {
            #if DEBUG
            print("[AppState] Failed to save session: \(error.localizedDescription)")
            #endif
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let exportRequested = Notification.Name("exportRequested")
    static let importRequested = Notification.Name("importRequested")
}
