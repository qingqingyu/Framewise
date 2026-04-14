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
    @State private var showFileImporter = false

    var body: some View {
        NavigationView {
            // Sidebar with drop zone
            SidebarView()
                .environmentObject(importViewModel)
                .frame(minWidth: 200)

            // Main content area - Grid only
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
        appState.clearSession()
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var importViewModel: VideoImportViewModel

    @State private var isTargeted = false
    @State private var showCreateTag = false
    @State private var renamingTagID: UUID? = nil
    @State private var renamingTagName = ""

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

                Section("Tags") {
                    ForEach(session.tags) { tag in
                        Button(action: {
                            if session.activeTagFilter == tag.id {
                                session.activeTagFilter = nil
                            } else {
                                session.activeTagFilter = tag.id
                            }
                        }) {
                            HStack {
                                Circle()
                                    .fill(tag.color.systemColor)
                                    .frame(width: 10, height: 10)
                                Text(tag.name)
                                Spacer()
                                Text("\(session.clipCount(for: tag.id))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if session.activeTagFilter == tag.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename") {
                                renamingTagID = tag.id
                                renamingTagName = tag.name
                            }
                            Button("Delete", role: .destructive) {
                                session.removeTag(tag.id)
                            }
                        }
                    }

                    Button(action: { showCreateTag = true }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("New Tag...")
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        session.loadWeddingPreset()
                    }) {
                        HStack {
                            Image(systemName: "bolt.circle")
                            Text("Load Wedding Preset")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .sheet(isPresented: $showCreateTag) {
            TagCreateView { tag in
                appState.importSession?.addTag(tag)
            }
        }
        .alert("Rename Tag", isPresented: Binding(
            get: { renamingTagID != nil },
            set: { if !$0 { renamingTagID = nil } }
        ), actions: {
            TextField("Name", text: $renamingTagName)
            Button("Cancel") {
                renamingTagID = nil
            }
            Button("Rename") {
                if let tagID = renamingTagID {
                    let trimmed = renamingTagName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        appState.importSession?.renameTag(tagID, to: trimmed)
                    }
                }
                renamingTagID = nil
            }
        }) {
            EmptyView()
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
        let supportedExtensions = Set(["mp4", "mov", "mxf", "avi", "mkv", "m4v"])

        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }
                if let url, supportedExtensions.contains(url.pathExtension.lowercased()) {
                    urls.append(url)
                }
            }
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
    @State private var saveError: String?

    /// Clips to export, excluding waste clips (blackout/dark/solid)
    private var clipsToExport: [VideoClip] {
        appState.selectedClips.filter { $0.wasteType == .none }
    }

    /// Number of waste clips excluded from export
    private var excludedWasteCount: Int {
        appState.selectedClips.count - clipsToExport.count
    }

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

            if excludedWasteCount > 0 {
                Text("\(appState.selectedClips.count) selected, \(excludedWasteCount) waste clips excluded")
                    .foregroundColor(.secondary)
            } else {
                Text("\(clipsToExport.count) clips will be exported")
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Export") {
                    Task {
                        if let url = await exportViewModel.export(
                            clips: clipsToExport,
                            format: exportViewModel.exportFormat
                        ) {
                            exportedFileURL = url
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = url.lastPathComponent
                            panel.allowedContentTypes = [.init(filenameExtension: exportViewModel.exportFormat.fileExtension) ?? .data]
                            panel.begin { response in
                                defer {
                                    // Always clean up temp file after save panel closes
                                    try? FileManager.default.removeItem(at: url)
                                }
                                if response == .OK, let destURL = panel.url {
                                    do {
                                        // Remove existing file to avoid copyItem failure
                                        if FileManager.default.fileExists(atPath: destURL.path) {
                                            try FileManager.default.removeItem(at: destURL)
                                        }
                                        try FileManager.default.copyItem(at: url, to: destURL)
                                        dismiss()
                                    } catch {
                                        saveError = "Failed to save file: \(error.localizedDescription)"
                                    }
                                }
                            }
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(clipsToExport.isEmpty || exportViewModel.isExporting)
            }
        }
        .padding(30)
        .frame(width: 400)
        .alert("Export Error", isPresented: Binding(
            get: { exportViewModel.error != nil },
            set: { if !$0 { exportViewModel.error = nil } }
        ), presenting: exportViewModel.error) { _ in
            Button("OK") { exportViewModel.error = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert("Save Error", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        ), presenting: saveError) { _ in
            Button("OK") { saveError = nil }
        } message: { message in
            Text(message)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("segmentCount") private var segmentCount = 36
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
                Slider(value: Binding(
                    get: { Double(segmentCount) },
                    set: { segmentCount = Int($0) }
                ), in: 12...120, step: 12) {
                    Text("Target Segment Count")
                }
                Text("Each video will be split into roughly this many segments (\(segmentCount))")
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
