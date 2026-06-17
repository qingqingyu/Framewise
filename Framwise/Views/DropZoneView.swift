//
//  DropZoneView.swift
//  Framwise
//
//  Drag and drop zone for importing videos
//

import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var importViewModel: VideoImportViewModel

    @State private var isTargeted = false
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: Layout.outerSpacing) {
            Spacer()

            VStack(spacing: Layout.headerSpacing) {
                Text("Drop Video Files or Folders")
                    .font(.framwiseDisplay(42, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Layout.titleMaxWidth)

                Text("Import footage first, then review, reject, tag, and hand off the clips worth keeping.")
                    .font(.framwiseUI(14))
                    .foregroundStyle(FramwiseTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Layout.subtitleMaxWidth)

                ZStack {
                    RoundedRectangle(cornerRadius: Layout.dropZoneRadius, style: .continuous)
                        .fill(FramwiseTheme.surface.opacity(Layout.surfaceFillOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.dropZoneRadius, style: .continuous)
                                .fill(FramwiseTheme.subtleHighlight.opacity(Layout.highlightOverlayOpacity))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.dropZoneRadius, style: .continuous)
                                .strokeBorder(style: Layout.dropTargetStroke)
                                .foregroundStyle(isTargeted ? FramwiseTheme.accent : FramwiseTheme.line)
                        )
                        .frame(width: Layout.dropZoneSize.width, height: Layout.dropZoneSize.height)

                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(isTargeted ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised)
                            Image(systemName: "film.stack.fill")
                                .font(.framwiseDisplay(Layout.dropZoneSymbolSize, weight: .semibold))
                                .foregroundStyle(isTargeted ? FramwiseTheme.accent : FramwiseTheme.warm)
                        }
                        .frame(width: Layout.dropZoneIconSize, height: Layout.dropZoneIconSize)

                        VStack(spacing: 12) {
                            Text(isTargeted ? "Release to import" : "Ready for footage")
                                .font(.framwiseUI(13, weight: .medium))
                                .foregroundStyle(isTargeted ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted)

                            HStack(spacing: 8) {
                                formatChip("MOV")
                                formatChip("MP4")
                                formatChip("MPEG4")
                                formatChip("QuickTime")
                                formatChip("Folders")
                            }
                        }

                        Button(action: { showFileImporter = true }) {
                            Label("Choose Files", systemImage: "plus")
                        }
                        .buttonStyle(FramwisePrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }
                .animation(.easeInOut(duration: 0.15), value: isTargeted)
            }

            if importViewModel.isResolvingSources {
                FramwiseStatePanel(
                    state: .loading,
                    title: "Reading sources",
                    message: "Scanning selected files and folders before import.",
                    compact: true
                )
                .frame(maxWidth: Layout.statePanelMaxWidth)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if importViewModel.isImporting {
                VStack(spacing: 14) {
                    if importViewModel.totalFilesCount > 1 {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Files")
                                    .font(.framwiseUI(12))
                                    .foregroundStyle(FramwiseTheme.textMuted)
                                Spacer()
                                Text("\(Int(importViewModel.importProgress * 100))%")
                                    .font(.framwiseMono(11))
                                    .foregroundStyle(FramwiseTheme.textMuted)
                            }
                            FramwiseLinearProgress(value: importViewModel.importProgress, tint: FramwiseTheme.accent)
                        }
                        .frame(width: Layout.progressStripWidth)
                    }

                    if importViewModel.isAnalyzing {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Analyzing \(importViewModel.currentVideoName)")
                                    .font(.framwiseUI(12))
                                    .foregroundStyle(FramwiseTheme.textMuted)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(importViewModel.analyzingProgress * 100))%")
                                    .font(.framwiseMono(11))
                                    .foregroundStyle(FramwiseTheme.textMuted)
                            }
                            FramwiseLinearProgress(value: importViewModel.analyzingProgress, tint: FramwiseTheme.warning)
                        }
                        .frame(width: Layout.progressStripWidth)

                        HStack(spacing: 8) {
                            Image(systemName: "film.fill")
                                .foregroundStyle(FramwiseTheme.accent)
                            if let session = appState.importSession, session.clipCount > importViewModel.clipsFoundCount {
                                Text("\(importViewModel.clipsFoundCount) new / \(session.clipCount) total clips")
                                    .font(.framwiseUI(14, weight: .medium))
                                    .foregroundStyle(FramwiseTheme.textPrimary)
                            } else {
                                Text("\(importViewModel.clipsFoundCount) clips found")
                                    .font(.framwiseUI(14, weight: .medium))
                                    .foregroundStyle(FramwiseTheme.textPrimary)
                            }
                        }
                    }
                }
                .padding(18)
                .framwisePanel(background: FramwiseTheme.surface, radius: 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(spacing: 8) {
                if let error = importViewModel.error {
                    FramwiseStatePanel(
                        state: .error,
                        title: "Import failed",
                        message: error.localizedDescription,
                        compact: true
                    )
                    .frame(maxWidth: Layout.statePanelMaxWidth)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !importViewModel.importWarnings.isEmpty {
                    FramwiseStatePanel(
                        state: .error,
                        title: "\(importViewModel.importWarningDisplayCount) file\(importViewModel.importWarningDisplayCount == 1 ? "" : "s") skipped",
                        message: importViewModel.importWarnings.map { "\($0.title): \($0.message)" }.prefix(2).joined(separator: "\n"),
                        systemImage: "exclamationmark.triangle.fill",
                        compact: true
                    )
                    .frame(maxWidth: Layout.statePanelMaxWidth)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FramwiseTheme.appGradient)
        .animation(.easeInOut(duration: 0.3), value: importViewModel.isResolvingSources)
        .animation(.easeInOut(duration: 0.3), value: importViewModel.isImporting)
        .animation(.easeInOut(duration: 0.3), value: importViewModel.error != nil)
        .animation(.easeInOut(duration: 0.3), value: importViewModel.importWarnings.isEmpty)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .folder],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result)
        }
    }

    // MARK: - File Handling

    private func formatChip(_ label: String) -> some View {
        Text(label)
            .font(.framwiseMono(10))
            .foregroundStyle(FramwiseTheme.textMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(FramwiseTheme.surfaceRaised.opacity(Layout.chipFillOpacity))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(FramwiseTheme.line.opacity(Layout.chipStrokeOpacity), lineWidth: 1)
            )
    }

    private func handleDrop(providers: [NSItemProvider]) {
        Task {
            let resolution = await DropProviderResolver.resolveURLs(from: providers, surface: "dropzone")
            if resolution.urls.isEmpty, let error = resolution.allProvidersFailedError {
                importViewModel.importWarnings = resolution.warnings
                importViewModel.importWarningTotalCount = resolution.errors.count
                importViewModel.error = error
                return
            }
            appState.importResolvedURLs(
                resolution.urls,
                into: importViewModel,
                preflightWarnings: resolution.warnings
            )
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            appState.importResolvedURLs(urls, into: importViewModel)
        case .failure(let error):
            guard importViewModel.recordFileSelectionFailure(error) else { return }
            AppLogger.error(AppLogger.importFlow, "File importer failed", error: error, context: [
                "surface": "dropzone"
            ])
        }
    }

}

// MARK: - Layout Constants

/// Local layout tokens for DropZoneView.
/// Sizes follow DESIGN.md spacing scale (8px base + intermediate 2/6/9/10/14/18/20)
/// and radius scale (panel = 18). Opacity values are intentionally local since they
/// model a one-off decorative translucency layer over `FramwiseTheme.subtleHighlight`.
private enum Layout {
    /// Outer VStack spacing — was 28 (off-scale), normalized to core scale `lg`.
    static let outerSpacing: CGFloat = 24
    /// Header VStack spacing between title / subtitle / drop card.
    static let headerSpacing: CGFloat = 20

    static let titleMaxWidth: CGFloat = 640
    static let subtitleMaxWidth: CGFloat = 520

    /// Drop card size — both dimensions divisible by 4.
    static let dropZoneSize = CGSize(width: 580, height: 320)
    /// Drop card radius — DESIGN.md `panel` token (was 28, off-scale).
    static let dropZoneRadius: CGFloat = 18
    /// Compound icon widget (Circle background + SF Symbol) — divisible by 4 (was 74, off-scale).
    static let dropZoneIconSize: CGFloat = 72
    /// SF Symbol font size inside the icon widget — preserves original 30/74 ≈ 0.4 proportion.
    static let dropZoneSymbolSize: CGFloat = 30

    /// Surface fill translucency over `appGradient` backdrop.
    static let surfaceFillOpacity: Double = 0.88
    /// Dampens the already-soft `subtleHighlight` gradient overlay.
    static let highlightOverlayOpacity: Double = 0.55
    /// Dashed drop target border. `lineWidth` normalized from 1.6 to 1.5.
    static let dropTargetStroke = StrokeStyle(lineWidth: 1.5, dash: [12, 8])

    static let statePanelMaxWidth: CGFloat = 460
    static let progressStripWidth: CGFloat = 360

    /// Chip background translucency.
    static let chipFillOpacity: Double = 0.7
    /// Chip border translucency.
    static let chipStrokeOpacity: Double = 0.65
}

#Preview {
    DropZoneView()
        .environmentObject(AppState())
        .environmentObject(VideoImportViewModel())
        .frame(width: 600, height: 500)
}
