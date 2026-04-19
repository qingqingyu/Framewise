//
//  ContentView.swift
//  Framwise
//
//  Main application view
//

import SwiftUI
import AVFoundation

enum FramwiseTheme {
    static let background = Color(hex: "0D0F12")
    static let backgroundElevated = Color(hex: "11141B")
    static let surface = Color(hex: "151922")
    static let surfaceRaised = Color(hex: "1D2330")
    static let line = Color(hex: "2A3142")
    static let textPrimary = Color(hex: "E7ECF3")
    static let textMuted = Color(hex: "9AA6B8")
    static let accent = Color(hex: "8C7CFF")
    static let accentSoft = Color(hex: "8C7CFF").opacity(0.16)
    static let success = Color(hex: "4DE2C5")
    static let warning = Color(hex: "FFB84D")
    static let danger = Color(hex: "FF6B6B")
    static let info = Color(hex: "7FB3FF")
    static let warm = Color(hex: "F3D2A7")

    static let appGradient = LinearGradient(
        colors: [
            background,
            Color(hex: "10131A"),
            background
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleHighlight = LinearGradient(
        colors: [
            warm.opacity(0.18),
            accent.opacity(0.06),
            .clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let monitorGradient = LinearGradient(
        colors: [
            Color.black.opacity(0.0),
            Color.black.opacity(0.55),
            Color.black.opacity(0.84)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Font {
    static func framwiseDisplay(_ size: CGFloat, weight: Weight = .semibold) -> Font {
        .custom("Instrument Sans", size: size).weight(weight)
    }

    static func framwiseUI(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom("Instrument Sans", size: size).weight(weight)
    }

    static func framwiseMono(_ size: CGFloat, weight: Weight = .medium) -> Font {
        .custom("IBM Plex Mono", size: size).weight(weight)
    }
}

struct FramwisePanelModifier: ViewModifier {
    var background: Color = FramwiseTheme.surface
    var radius: CGFloat = 18
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(FramwiseTheme.line.opacity(0.9), lineWidth: 1)
            )
    }
}

extension View {
    func framwisePanel(
        background: Color = FramwiseTheme.surface,
        radius: CGFloat = 18,
        padding: CGFloat = 0
    ) -> some View {
        modifier(FramwisePanelModifier(background: background, radius: radius, padding: padding))
    }
}

struct FramwisePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.framwiseUI(13, weight: .semibold))
            .foregroundStyle(FramwiseTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FramwiseTheme.accent.opacity(configuration.isPressed ? 0.55 : 0.78),
                                FramwiseTheme.warm.opacity(configuration.isPressed ? 0.18 : 0.26)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(FramwiseTheme.accent.opacity(0.55), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FramwiseGhostButtonStyle: ButtonStyle {
    var fill: Color = FramwiseTheme.surfaceRaised
    var border: Color = FramwiseTheme.line.opacity(0.9)
    var foreground: Color = FramwiseTheme.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.framwiseUI(13, weight: .medium))
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.92 : 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.9 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FramwiseMetricBadge: View {
    let title: String
    let value: String
    var color: Color = FramwiseTheme.textMuted

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.framwiseMono(10))
                .foregroundStyle(FramwiseTheme.textMuted)
            Text(value)
                .font(.framwiseDisplay(18, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 14)
    }
}

struct FramwiseLinearProgress: View {
    let value: Double
    var tint: Color = FramwiseTheme.accent

    private var clampedValue: Double {
        max(0, min(1, value))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(FramwiseTheme.surfaceRaised)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, FramwiseTheme.warm.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geometry.size.width * clampedValue))
            }
            .overlay(
                Capsule(style: .continuous)
                    .stroke(FramwiseTheme.line.opacity(0.6), lineWidth: 1)
            )
        }
        .frame(height: 10)
    }
}

struct FramwiseLoadingIndicator: View {
    var tint: Color = FramwiseTheme.accent
    var diameter: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .stroke(FramwiseTheme.line.opacity(0.35), lineWidth: 2)

            Circle()
                .trim(from: 0.12, to: 0.78)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

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
            importFiles(urls: urls)
        case .failure(let error):
            importViewModel.error = error
        }
    }

    private func importFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }

        if appState.importSession == nil {
            appState.importSession = ImportSession()
        }

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
                            SidebarMetricRow(label: "Waste", value: "\(session.allClips.filter { $0.wasteType != .none }.count)", tone: FramwiseTheme.warning)
                        }
                    }

                    sidebarSection(title: "Tags", subtitle: "\(session.tags.count) sorting lanes") {
                        VStack(spacing: 8) {
                            ForEach(session.tags) { tag in
                                SidebarTagRow(
                                    tag: tag,
                                    count: session.clipCount(for: tag.id),
                                    isActive: session.activeTagFilter == tag.id
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
                    Text(isTargeted ? "Release to import footage into the active workspace." : "Drop reels here or use Import to start a new cut-prep session.")
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
            var urls: [URL] = []
            var unsupportedNames: [String] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url)
                    }
                }
                if let url {
                    if supportedVideoExtensions.contains(url.pathExtension.lowercased()) {
                        urls.append(url)
                    } else {
                        unsupportedNames.append(url.lastPathComponent)
                    }
                }
            }
            if !urls.isEmpty {
                importFilesFromURLs(urls)
            } else if !unsupportedNames.isEmpty {
                importViewModel.error = ImportError.unsupportedFormat(unsupportedNames.joined(separator: ", "))
            }
        }
    }

    private func importFilesFromURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        if appState.importSession == nil {
            appState.importSession = ImportSession()
        }

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
        appState.selectedClips.filter { $0.wasteType == .none }
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
    @AppStorage("segmentCount") private var segmentCount = 36
    @AppStorage("sceneDetectionSensitivity") private var sceneDetectionSensitivity = SceneDetectionSettings.defaultUISensitivity

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WORKSPACE TUNING")
                    .font(.framwiseMono(10))
                    .foregroundStyle(FramwiseTheme.warm)
                Text("Settings")
                    .font(.framwiseDisplay(24, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                Text("Adjust scene detection and default clip segmentation for the first-pass workflow.")
                    .font(.framwiseUI(13))
                    .foregroundStyle(FramwiseTheme.textMuted)
            }

            VStack(alignment: .leading, spacing: 16) {
                settingsCard(
                    title: "Scene Detection",
                    value: String(format: "%.2f", sceneDetectionSensitivity)
                ) {
                    Slider(value: $sceneDetectionSensitivity, in: 0.1...0.9, step: 0.05) {
                        Text("Detection Sensitivity")
                    }
                    .tint(FramwiseTheme.accent)

                    Text("Higher values detect more scene changes.")
                        .font(.framwiseUI(12))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }

                settingsCard(
                    title: "Segment Splitting",
                    value: "\(segmentCount)"
                ) {
                    Slider(value: Binding(
                        get: { Double(segmentCount) },
                        set: { segmentCount = Int($0) }
                    ), in: 12...120, step: 12) {
                        Text("Target Segment Count")
                    }
                    .tint(FramwiseTheme.warning)

                    Text("Each video will be split into roughly this many segments.")
                        .font(.framwiseUI(12))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }
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
