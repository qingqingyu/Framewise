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
        VStack(spacing: 0) {
            appChromeBar

            NavigationView {
                SidebarView()
                    .environmentObject(importViewModel)
                    .frame(minWidth: 280, idealWidth: 300)

                ZStack {
                    FramwiseTheme.appGradient
                        .ignoresSafeArea()

                    if let session = appState.importSession, !session.allClips.isEmpty {
                        ClipGridView()
                            .environmentObject(gridViewModel)
                    } else {
                        DropZoneView()
                            .environmentObject(importViewModel)
                    }
                }
            }
        }
        .background(FramwiseTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView()
                .environmentObject(exportViewModel)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .folder],
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

    private var appChromeBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [FramwiseTheme.warm.opacity(0.35), FramwiseTheme.accent.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("F")
                        .font(.framwiseDisplay(18, weight: .bold))
                        .foregroundStyle(.black.opacity(0.82))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DIGITAL LIGHT TABLE")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.warm)
                    Text("Framwise")
                        .font(.framwiseDisplay(20, weight: .semibold))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                }
            }

            Spacer(minLength: 12)

            if importViewModel.isAnalyzing {
                HStack(spacing: 10) {
                    FramwiseLoadingIndicator(tint: FramwiseTheme.warning, diameter: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analyzing \(importViewModel.currentVideoName)")
                            .font(.framwiseUI(12, weight: .medium))
                            .foregroundStyle(FramwiseTheme.textPrimary)
                            .lineLimit(1)

                        if let session = appState.importSession, session.clipCount > importViewModel.clipsFoundCount {
                            Text("\(importViewModel.clipsFoundCount) new / \(session.clipCount) total")
                                .font(.framwiseMono(11))
                                .foregroundStyle(FramwiseTheme.textMuted)
                        } else {
                            Text("\(importViewModel.clipsFoundCount) clips found")
                                .font(.framwiseMono(11))
                                .foregroundStyle(FramwiseTheme.textMuted)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 16)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Button(action: { showFileImporter = true }) {
                    Label("Import", systemImage: "plus")
                }
                .buttonStyle(FramwisePrimaryButtonStyle())

                if appState.importSession != nil {
                    Text("\(appState.selectedClipIDs.count) selected")
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 999)

                    Button(action: { showExportSheet = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: appState.selectedClipIDs.isEmpty ? FramwiseTheme.surface : FramwiseTheme.surfaceRaised,
                        border: appState.selectedClipIDs.isEmpty ? FramwiseTheme.line.opacity(0.7) : FramwiseTheme.accent.opacity(0.3),
                        foreground: appState.selectedClipIDs.isEmpty ? FramwiseTheme.textMuted : FramwiseTheme.textPrimary
                    ))
                    .disabled(appState.selectedClipIDs.isEmpty)

                    Button(action: { clearSession() }) {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: FramwiseTheme.surface,
                        border: FramwiseTheme.line.opacity(0.8),
                        foreground: FramwiseTheme.textMuted
                    ))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            ZStack {
                FramwiseTheme.backgroundElevated
                FramwiseTheme.subtleHighlight.opacity(0.6)
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FramwiseTheme.line.opacity(0.9))
                .frame(height: 1)
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let (videoURLs, _) = FileResolver.resolveVideoURLs(from: urls)
            importFiles(urls: videoURLs)
        case .failure(let error):
            importViewModel.error = error
        }
    }

    private func importFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        appState.ensureSession()
        importViewModel.importVideosStreaming(from: urls, into: appState.importSession!)
    }

    private func clearSession() {
        importViewModel.cancelImport()
        gridViewModel.resetTransientUIState()
        appState.clearSession()
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var importViewModel: VideoImportViewModel

    @State private var isTargeted = false
    @State private var showCreateTag = false
    @State private var renamingTag: ClipTag?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("INGEST + SORT")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.warm)
                    Text("Workspace")
                        .font(.framwiseDisplay(24, weight: .semibold))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                    Text("Sources, tags, and clip inventory stay visible while the footage does the talking.")
                        .font(.framwiseUI(13))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                dropZone

                if let session = appState.importSession {
                    sidebarSection(title: "Source Files", subtitle: "\(session.sourceFiles.count) active reels") {
                        VStack(spacing: 8) {
                            SidebarRow(
                                title: "All Clips",
                                icon: "square.grid.2x2.fill",
                                value: "\(session.clipCount)",
                                isActive: appState.selectedSourceURL == nil
                            ) {
                                appState.selectedSourceURL = nil
                            }

                            ForEach(session.sourceFiles, id: \.self) { url in
                                SidebarRow(
                                    title: url.lastPathComponent,
                                    icon: "video.fill",
                                    value: "\(session.allClips.filter { $0.sourceFileURL == url }.count)",
                                    isActive: appState.selectedSourceURL == url
                                ) {
                                    appState.selectedSourceURL = url
                                }
                            }
                        }
                    }

                    sidebarSection(title: "Statistics", subtitle: "Live workspace state") {
                        VStack(spacing: 10) {
                            SidebarMetricRow(label: "Total Clips", value: "\(session.clipCount)")
                            SidebarMetricRow(label: "Total Duration", value: formatDuration(session.totalDuration))
                            SidebarMetricRow(label: "Selected", value: "\(appState.selectedClipIDs.count)", tone: FramwiseTheme.accent)
                            SidebarMetricRow(label: "Tagged", value: "\(session.allClips.filter { !$0.tagIDs.isEmpty }.count)", tone: FramwiseTheme.success)
                            SidebarMetricRow(label: "Waste", value: "\(session.allClips.filter { $0.effectiveWasteType != .none }.count)", tone: FramwiseTheme.warning)
                        }
                    }

                    sidebarSection(title: "Tags", subtitle: "\(session.tags.count) sorting lanes") {
                        VStack(spacing: 8) {
                            if session.tags.isEmpty {
                                TagsEmptyStateView(
                                    onLoadPreset: { session.loadWeddingPreset() },
                                    onCreateTag: { showCreateTag = true }
                                )
                            } else {
                                ForEach(Array(session.tags.enumerated()), id: \.element.id) { index, tag in
                                    SidebarTagRow(
                                        tag: tag,
                                        count: session.clipCount(for: tag.id),
                                        isActive: session.activeTagFilter == tag.id,
                                        shortcutNumber: index < 9 ? index + 1 : nil
                                    ) {
                                        if session.activeTagFilter == tag.id {
                                            session.activeTagFilter = nil
                                        } else {
                                            session.activeTagFilter = tag.id
                                        }
                                    }
                                    .contextMenu {
                                        Button("Rename") {
                                            renamingTag = tag
                                        }
                                        Button("Delete", role: .destructive) {
                                            session.removeTag(tag.id)
                                        }
                                    }
                                }

                                TagsKeyboardHint(tagCount: session.tags.count)

                                HStack(spacing: 8) {
                                    Button(action: { showCreateTag = true }) {
                                        Label("New Tag", systemImage: "plus")
                                    }
                                    .buttonStyle(FramwiseGhostButtonStyle())

                                    Button(action: {
                                        session.loadWeddingPreset()
                                    }) {
                                        Label("Wedding Preset", systemImage: "bolt.fill")
                                    }
                                    .buttonStyle(FramwiseGhostButtonStyle(
                                        fill: FramwiseTheme.surface,
                                        border: FramwiseTheme.warning.opacity(0.35),
                                        foreground: FramwiseTheme.warning
                                    ))
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                } else {
                    sidebarSection(title: "No Session", subtitle: "Start with footage import") {
                        Text("Drop files above or use the Import button to create your first working session.")
                            .font(.framwiseUI(13))
                            .foregroundStyle(FramwiseTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
        }
        .background(
            ZStack {
                FramwiseTheme.backgroundElevated
                FramwiseTheme.subtleHighlight.opacity(0.45)
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .sheet(isPresented: $showCreateTag) {
            TagCreateView(
                existingNames: Set(appState.importSession?.tags.map(\.name) ?? [])
            ) { tag in
                appState.importSession?.addTag(tag) ?? false
            }
        }
        .sheet(item: $renamingTag) { tag in
            TagRenameView(
                initialName: tag.name,
                existingNames: Set((appState.importSession?.tags ?? []).filter { $0.id != tag.id }.map(\.name))
            ) { newName in
                appState.importSession?.renameTag(tag.id, to: newName) ?? false
            }
        }
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isTargeted ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised)
                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isTargeted ? FramwiseTheme.accent : FramwiseTheme.warm)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ingest Bay")
                        .font(.framwiseDisplay(18, weight: .semibold))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                    Text(isTargeted ? "Release to import footage into the active workspace." : "Drop reels or folders here, or use Import to start a new session.")
                        .font(.framwiseUI(13))
                        .foregroundStyle(isTargeted ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Text("MOV")
                Text("MP4")
                Text("MPEG4")
                Text("QuickTime")
            }
            .font(.framwiseMono(10))
            .foregroundStyle(FramwiseTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FramwiseTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 4])
                )
                .foregroundStyle(isTargeted ? FramwiseTheme.accent : FramwiseTheme.line)
        )
        .overlay(alignment: .topTrailing) {
            if isTargeted {
                Text("READY")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(FramwiseTheme.accentSoft)
                    )
                    .padding(12)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.textMuted)
                Text(subtitle)
                    .font(.framwiseUI(12))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }
            content()
        }
        .padding(14)
        .framwisePanel(background: FramwiseTheme.surface, radius: 18)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            var droppedURLs: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }
                if let url { droppedURLs.append(url) }
            }
            let (videoURLs, unsupported) = FileResolver.resolveVideoURLs(from: droppedURLs)
            if !videoURLs.isEmpty {
                importFilesFromURLs(videoURLs)
            } else if !unsupported.isEmpty {
                importViewModel.error = ImportError.unsupportedFormat(unsupported.joined(separator: ", "))
            }
        }
    }

    private func importFilesFromURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        appState.ensureSession()
        importViewModel.importVideosStreaming(from: urls, into: appState.importSession!)
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

struct ExportSheetView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var exportViewModel: ExportViewModel
    @Environment(\.dismiss) var dismiss

    @State private var exportedFileURL: URL?
    @State private var saveError: String?

    private var clipsToExport: [VideoClip] {
        appState.selectedClips.filter { $0.effectiveWasteType == .none }
    }

    private var excludedWasteCount: Int {
        appState.selectedClips.count - clipsToExport.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Delivery")
                    .font(.framwiseDisplay(28, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Text("Choose a handoff format, confirm how many clips are leaving the workspace, and deliver only what survives the cut.")
                    .font(.framwiseUI(14))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }

            HStack(spacing: 12) {
                FramwiseMetricBadge(title: "Selected", value: "\(appState.selectedClips.count)")
                FramwiseMetricBadge(title: "Exportable", value: "\(clipsToExport.count)", color: FramwiseTheme.textPrimary)
                FramwiseMetricBadge(title: "Waste Excluded", value: "\(max(excludedWasteCount, 0))", color: excludedWasteCount > 0 ? FramwiseTheme.warning : FramwiseTheme.textMuted)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("FORMAT")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.textMuted)

                ForEach(ExportViewModel.ExportFormat.allCases, id: \.self) { format in
                    Button(action: {
                        exportViewModel.exportFormat = format
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: exportViewModel.exportFormat == format ? "record.circle.fill" : "circle")
                                .foregroundStyle(exportViewModel.exportFormat == format ? FramwiseTheme.accent : FramwiseTheme.textMuted)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(format.displayName)
                                    .font(.framwiseUI(14, weight: .semibold))
                                    .foregroundStyle(FramwiseTheme.textPrimary)
                                Text(formatDescription(for: format))
                                    .font(.framwiseUI(12))
                                    .foregroundStyle(FramwiseTheme.textMuted)
                            }
                            Spacer()
                            Text(format.fileExtension.uppercased())
                                .font(.framwiseMono(11))
                                .foregroundStyle(FramwiseTheme.textMuted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(exportViewModel.exportFormat == format ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(exportViewModel.exportFormat == format ? FramwiseTheme.accent.opacity(0.35) : FramwiseTheme.line.opacity(0.85), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .framwisePanel(background: FramwiseTheme.surface, radius: 22)

            VStack(alignment: .leading, spacing: 10) {
                if clipsToExport.isEmpty && excludedWasteCount > 0 {
                    statusCallout(
                        title: "Nothing exportable yet",
                        body: "All \(appState.selectedClips.count) selected clips are currently marked as waste.",
                        color: FramwiseTheme.warning
                    )
                } else if excludedWasteCount > 0 {
                    statusCallout(
                        title: "Waste clips excluded",
                        body: "\(appState.selectedClips.count) selected, \(excludedWasteCount) marked as waste and removed from delivery.",
                        color: FramwiseTheme.warning
                    )
                } else {
                    statusCallout(
                        title: "Ready to export",
                        body: "\(clipsToExport.count) approved clips will be written to the delivery file.",
                        color: FramwiseTheme.success
                    )
                }

                if let warning = exportViewModel.warning {
                    statusCallout(
                        title: "Export warning",
                        body: warning,
                        color: FramwiseTheme.warning
                    )
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(FramwiseGhostButtonStyle())

                Spacer()

                Button(action: startExport) {
                    Label(exportViewModel.isExporting ? "Exporting..." : "Export", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(FramwisePrimaryButtonStyle())
                .disabled(clipsToExport.isEmpty || exportViewModel.isExporting)
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(FramwiseTheme.background)
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

    private func formatDescription(for format: ExportViewModel.ExportFormat) -> String {
        switch format {
        case .edl:
            return "最轻量的时间线交换格式，适合兼容交接。"
        case .fcpxml:
            return "适合 Final Cut / DaVinci 等继续整理与重建时间线。"
        }
    }

    @ViewBuilder
    private func statusCallout(title: String, body: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.framwiseUI(13, weight: .semibold))
                .foregroundStyle(FramwiseTheme.textPrimary)
            Text(body)
                .font(.framwiseUI(12))
                .foregroundStyle(FramwiseTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.24), lineWidth: 1)
        )
    }

    private func startExport() {
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
                        try? FileManager.default.removeItem(at: url)
                        exportViewModel.isExporting = false
                    }
                    if response == .OK, let destURL = panel.url {
                        do {
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
            } else {
                exportViewModel.isExporting = false
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("segmentCount") private var segmentCount = SceneDetectionSettings.defaultTileCount

    private static let sliderRange = Double(SceneDetectionSettings.minTileCount)...Double(SceneDetectionSettings.maxTileCount)
    private static let sliderStep = Double(SceneDetectionSettings.tileCountStep)

    private var densityLabel: String {
        switch segmentCount {
        case ...18: return "Broad overview"
        case 19...48: return "Balanced"
        case 49...84: return "Detailed"
        default: return "Fine detail"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PREFERENCES")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.warm)
                Text("Settings")
                    .font(.framwiseDisplay(24, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Text("Configure how videos are split into preview tiles.")
                    .font(.framwiseUI(13))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }

            settingsCard(
                title: "Preview Tiles",
                value: "\(segmentCount)"
            ) {
                Slider(value: Binding(
                    get: { Double(segmentCount) },
                    set: { segmentCount = Int($0) }
                ), in: Self.sliderRange, step: Self.sliderStep) {
                    Text("Target Tile Count")
                }
                .tint(FramwiseTheme.warm)

                HStack(spacing: 8) {
                    Text(densityLabel)
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.warm)

                    Text("—")
                        .foregroundStyle(FramwiseTheme.textMuted.opacity(0.4))

                    Text("More tiles = finer detail. Scene detection sensitivity adjusts automatically.")
                        .font(.framwiseUI(12))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }

                Text("Changes apply to next import.")
                    .font(.framwiseUI(11))
                    .foregroundStyle(FramwiseTheme.textMuted.opacity(0.5))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FramwiseTheme.background)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.framwiseDisplay(18, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Spacer()
                Text(value)
                    .font(.framwiseMono(11))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }
            content()
        }
        .padding(16)
        .framwisePanel(background: FramwiseTheme.surface, radius: 18)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let value: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isActive ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? FramwiseTheme.accent : FramwiseTheme.textMuted)
                }
                .frame(width: 28, height: 28)

                Text(title)
                    .font(.framwiseUI(13, weight: .medium))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(value)
                    .font(.framwiseMono(11))
                    .foregroundStyle(isActive ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? FramwiseTheme.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? FramwiseTheme.accent.opacity(0.3) : FramwiseTheme.line.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarTagRow: View {
    let tag: ClipTag
    let count: Int
    let isActive: Bool
    var shortcutNumber: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(tag.color.systemColor)
                    .frame(width: 10, height: 10)

                Text(tag.name)
                    .font(.framwiseUI(13, weight: .medium))
                    .foregroundStyle(FramwiseTheme.textPrimary)

                Spacer()

                if let num = shortcutNumber {
                    Text("\(num)")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.textMuted.opacity(0.6))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(FramwiseTheme.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(FramwiseTheme.line.opacity(0.5), lineWidth: 0.5)
                        )
                }

                Text("\(count)")
                    .font(.framwiseMono(11))
                    .foregroundStyle(isActive ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? tag.color.systemColor.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isActive ? tag.color.systemColor.opacity(0.35) : FramwiseTheme.line.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tags Empty State

private struct TagsEmptyStateView: View {
    let onLoadPreset: () -> Void
    let onCreateTag: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(FramwiseTheme.textMuted.opacity(0.5))

                Text("No sorting tags yet")
                    .font(.framwiseUI(13, weight: .medium))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }
            .padding(.top, 4)

            Button(action: onLoadPreset) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                    Text("Load Wedding Preset")
                        .font(.framwiseUI(13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(FramwiseTheme.warm.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FramwiseTheme.warm.opacity(0.3), lineWidth: 1)
                )
                .foregroundStyle(FramwiseTheme.warm)
            }
            .buttonStyle(.plain)

            Text("Pre-built tags for ceremony, reception, first dance & more. Press 1–6 to tag clips instantly.")
                .font(.framwiseUI(11))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Button(action: onCreateTag) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Create custom tag")
                        .font(.framwiseUI(12))
                }
                .foregroundStyle(FramwiseTheme.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tags Keyboard Hint

private struct TagsKeyboardHint: View {
    let tagCount: Int

    private var hintText: Text {
        let maxKey = min(tagCount, 9)
        let muted = FramwiseTheme.textMuted.opacity(0.6)
        let warm = FramwiseTheme.warm.opacity(0.8)
        let prefix = Text("Focus or hover a clip, press ").font(.framwiseUI(11)).foregroundStyle(muted)
        let one = Text("1").font(.framwiseMono(11)).foregroundStyle(warm)
        let dash = Text("–").font(.framwiseUI(11)).foregroundStyle(muted)
        let end = Text("\(maxKey)").font(.framwiseMono(11)).foregroundStyle(warm)
        let suffix = Text(" to tag").font(.framwiseUI(11)).foregroundStyle(muted)
        return prefix + one + dash + end + suffix
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.5))

            hintText
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FramwiseTheme.warm.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(FramwiseTheme.warm.opacity(0.1), lineWidth: 0.5)
        )
    }
}

private struct SidebarMetricRow: View {
    let label: String
    let value: String
    var tone: Color = FramwiseTheme.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.framwiseUI(13))
                .foregroundStyle(FramwiseTheme.textMuted)
            Spacer()
            Text(value)
                .font(.framwiseMono(11))
                .foregroundStyle(tone)
        }
        .padding(.vertical, 2)
    }
}
