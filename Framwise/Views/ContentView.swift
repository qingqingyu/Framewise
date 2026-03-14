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
    @StateObject private var previewViewModel = PreviewViewModel()

    @State private var showExportSheet = false
    @State private var showFileImporter = false
    @State private var showPreviewPanel = true

    var body: some View {
        NavigationView {
            // Sidebar with drop zone
            SidebarView()
                .environmentObject(importViewModel)
                .frame(minWidth: 200)

            // Main content area
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Grid area
                    ZStack {
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
                    .frame(width: showPreviewPanel && appState.previewClip != nil
                           ? geometry.size.width - 320
                           : geometry.size.width)

                    // Preview panel (when clip is selected and panel is visible)
                    if showPreviewPanel && appState.previewClip != nil {
                        Divider()
                        ClipPreviewView(viewModel: previewViewModel)
                            .environmentObject(appState)
                            .frame(width: 320)
                    }
                }
            }
        }
        .navigationTitle("Framwise")
        .toolbar {
            ToolbarItemGroup {
                // Import button (always visible)
                Button(action: { showFileImporter = true }) {
                    Label("Import", systemImage: "plus.circle")
                }

                // Real-time analysis status
                if importViewModel.isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Analyzing \(importViewModel.currentVideoName)...")
                                .font(.caption)
                            Text("\(importViewModel.clipsFoundCount) clips found")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                }

                if appState.importSession != nil {
                    // Selection info
                    Text("\(appState.selectedClipIDs.count) selected")
                        .foregroundColor(.secondary)

                    // Preview toggle
                    Button(action: { showPreviewPanel.toggle() }) {
                        Image(systemName: showPreviewPanel ? "play.rectangle.fill" : "play.rectangle")
                    }
                    .buttonStyle(.plain)
                    .help(showPreviewPanel ? "Hide Preview Panel" : "Show Preview Panel")

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
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result)
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportRequested)) { _ in
            if !appState.selectedClipIDs.isEmpty {
                showExportSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importRequested)) { _ in
            showFileImporter = true
        }
        .onChange(of: appState.previewClip) { _, newClip in
            if let clip = newClip {
                previewViewModel.loadClip(clip)
            } else {
                previewViewModel.cleanupPlayer()
            }
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importFiles(urls: urls)
        case .failure(let error):
            importViewModel.error = error
        }
    }

    private func importFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }

        // 如果没有session，创建新的
        if appState.importSession == nil {
            appState.importSession = ImportSession()
        }

        Task {
            await importViewModel.importVideosStreaming(from: urls, into: appState.importSession!)
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
    @EnvironmentObject var importViewModel: VideoImportViewModel

    @State private var isTargeted = false

    var body: some View {
        List {
            // Drop zone at top
            Section {
                dropZone
            }

            if let session = appState.importSession {
                Section("Source Files") {
                    // All Clips option
                    Button(action: { appState.selectedSourceURL = nil }) {
                        HStack {
                            Label("All Clips", systemImage: "square.grid.2x2")
                            Spacer()
                            if appState.selectedSourceURL == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Divider()

                    ForEach(session.sourceFiles, id: \.self) { url in
                        Button(action: { appState.selectedSourceURL = url }) {
                            HStack {
                                Label(url.lastPathComponent, systemImage: "video.fill")
                                Spacer()
                                if appState.selectedSourceURL == url {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Statistics") {
                    LabeledContent("Total Clips", value: "\(session.clipCount)")
                    LabeledContent("Total Duration", value: formatDuration(session.totalDuration))
                    LabeledContent("Selected", value: "\(appState.selectedClipIDs.count)")
                }
            }
        }
        .listStyle(.sidebar)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.dashed")
                .font(.title2)
                .foregroundColor(isTargeted ? .accentColor : .secondary)

            Text(isTargeted ? "Drop to Import" : "Drop Videos Here")
                .font(.caption)
                .foregroundColor(isTargeted ? .accentColor : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    urls.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            importFilesFromURLs(urls)
        }
    }

    private func importFilesFromURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if appState.importSession == nil {
            appState.importSession = ImportSession()
        }

        Task {
            await importViewModel.importVideosStreaming(from: urls, into: appState.importSession!)
        }
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
