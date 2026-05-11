//
//  SidebarView.swift
//  Framwise
//
//  Sidebar workspace navigation and ingest controls
//

import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var importViewModel: VideoImportViewModel

    @State private var isTargeted = false
    @State private var showCreateTag = false
    @State private var renamingTag: ClipTag?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                workspaceHeader

                if appState.importSession != nil {
                    dropZone
                    if let error = importViewModel.error {
                        importErrorView(error)
                    }
                } else {
                    emptyWorkflowPreview
                }

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
        .optionalFileURLDrop(
            enabled: appState.importSession != nil,
            isTargeted: $isTargeted
        ) { providers in
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

    private func importErrorView(_ error: Error) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FramwiseTheme.danger)
            Text(error.localizedDescription)
                .font(.framwiseUI(12))
                .foregroundStyle(FramwiseTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FramwiseTheme.danger.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FramwiseTheme.danger.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var workspaceHeader: some View {
        if appState.importSession != nil {
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
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("WORKFLOW PREVIEW")
                    .font(.framwiseMono(9))
                    .foregroundStyle(FramwiseTheme.textMuted.opacity(0.9))
                Text("Workspace")
                    .font(.framwiseDisplay(20, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textMuted)
                Text("Outlines what unlocks after import.")
                    .font(.framwiseUI(12))
                    .foregroundStyle(FramwiseTheme.textMuted.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        }
    }

    private var emptyWorkflowPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            workflowPreviewRow(
                icon: "folder.fill",
                title: "Sources",
                caption: "Imported reels and folders land here."
            )
            workflowPreviewDivider
            workflowPreviewRow(
                icon: "tag",
                title: "Tags",
                caption: "Sorting lanes and filters populate after ingest."
            )
            workflowPreviewDivider
            workflowPreviewRow(
                icon: "square.grid.2x2",
                title: "Clip Inventory",
                caption: "Counts and routing stay visible beside the grid."
            )
        }
        .padding(14)
        .framwisePanel(background: FramwiseTheme.surface.opacity(0.55), radius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FramwiseTheme.line.opacity(0.35), lineWidth: 1)
        )
    }

    private var workflowPreviewDivider: some View {
        Rectangle()
            .fill(FramwiseTheme.line.opacity(0.35))
            .frame(height: 1)
            .padding(.vertical, 10)
    }

    private func workflowPreviewRow(icon: String, title: String, caption: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.65))
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.framwiseUI(13, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textMuted.opacity(0.92))
                Text(caption)
                    .font(.framwiseUI(12))
                    .foregroundStyle(FramwiseTheme.textMuted.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            } else {
                importViewModel.error = ImportError.noSupportedVideos
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

extension View {
    @ViewBuilder
    func optionalFileURLDrop(
        enabled: Bool,
        isTargeted: Binding<Bool>,
        perform: @escaping ([NSItemProvider]) -> Bool
    ) -> some View {
        if enabled {
            self.onDrop(of: [.fileURL], isTargeted: isTargeted, perform: perform)
        } else {
            self
        }
    }
}
