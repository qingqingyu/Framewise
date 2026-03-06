//
//  ContentView.swift
//  Framwise
//
//  Main application view
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var importViewModel = VideoImportViewModel()
    @StateObject private var gridViewModel = ClipGridViewModel()
    @StateObject private var exportViewModel = ExportViewModel()

    @State private var showExportSheet = false
    @State private var showImportProgress = false

    var body: some View {
        NavigationView {
            // Sidebar
            SidebarView()
                .frame(minWidth: 200)

            // Main content
            VStack(spacing: 0) {
                if let session = appState.importSession, !session.allClips.isEmpty {
                    // Grid view when clips are loaded
                    ClipGridView()
                        .environmentObject(gridViewModel)
                } else {
                    // Import zone when no clips
                    DropZoneView()
                        .environmentObject(importViewModel)
                }
            }
        }
        .navigationTitle("Framwise")
        .toolbar {
            ToolbarItemGroup {
                if appState.importSession != nil {
                    // Selection info
                    Text("\(appState.selectedClipIDs.count) selected")
                        .foregroundColor(.secondary)

                    Button(action: { showExportSheet = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(appState.selectedClipIDs.isEmpty)

                    Button(action: { clearSession() }) {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView()
                .environmentObject(exportViewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { _ in
            if !appState.selectedClipIDs.isEmpty {
                showExportSheet = true
            }
        }
        .onChange(of: importViewModel.isImporting) { _, isImporting in
            showImportProgress = isImporting
        }
    }

    private func clearSession() {
        appState.importSession?.clear()
        appState.importSession = nil
        appState.selectedClipIDs.removeAll()
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            if let session = appState.importSession {
                Section("Source Files") {
                    ForEach(session.sourceFiles, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "video.fill")
                    }
                }

                Section("Statistics") {
                    LabeledContent("Total Clips", value: "\(session.clipCount)")
                    LabeledContent("Total Duration", value: formatDuration(session.totalDuration))
                    LabeledContent("Selected", value: "\(appState.selectedClipIDs.count)")
                }
            } else {
                Text("No project loaded")
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.sidebar)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
}

// MARK: - Export Sheet

struct ExportSheetView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var exportViewModel: ExportViewModel
    @Environment(\.dismiss) var dismiss

    @State private var exportedFileURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Selected Clips")
                .font(.headline)

            Picker("Format", selection: $exportViewModel.exportFormat) {
                ForEach(ExportViewModel.ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.radioGroup)

            Text("\(appState.selectedClipIDs.count) clips will be exported")
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Export") {
                    Task {
                        if let url = await exportViewModel.export(
                            clips: appState.selectedClips,
                            format: exportViewModel.exportFormat
                        ) {
                            exportedFileURL = url
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = url.lastPathComponent
                            panel.allowedContentTypes = [.init(filenameExtension: exportViewModel.exportFormat.fileExtension) ?? .data]
                            panel.begin { response in
                                if response == .OK, let destURL = panel.url {
                                    try? FileManager.default.copyItem(at: url, to: destURL)
                                }
                            }
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.selectedClipIDs.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("maxSegmentDuration") private var maxSegmentDuration = 5.0
    @AppStorage("sceneDetectionSensitivity") private var sceneDetectionSensitivity = 0.3

    var body: some View {
        Form {
            Section("Scene Detection") {
                Slider(value: $sceneDetectionSensitivity, in: 0.1...0.9, step: 0.05) {
                    Text("Detection Sensitivity")
                }
                Text("Higher values = more sensitive to scene changes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Segment Splitting") {
                Slider(value: $maxSegmentDuration, in: 3...15, step: 1) {
                    Text("Max Segment Duration (seconds)")
                }
                Text("Long shots will be split at this interval")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
