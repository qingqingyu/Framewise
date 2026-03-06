//
//  FramwiseApp.swift
//  Framwise
//
//  Video clip browser and filter tool for editors
//

import SwiftUI

@main
struct FramwiseApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .importExport) {
                Button("Export Selected Clips...") {
                    NotificationCenter.default.post(name: .exportRequested, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .frame(width: 400, height: 300)
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var importSession: ImportSession?
    @Published var selectedClipIDs: Set<UUID> = []
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0

    var selectedClips: [VideoClip] {
        guard let session = importSession else { return [] }
        return session.allClips.filter { selectedClipIDs.contains($0.id) }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let exportRequested = Notification.Name("exportRequested")
}
