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
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 20) {
                Text("Drop Video Files or Folders")
                    .font(.framwiseDisplay(42, weight: .semibold))
                    .foregroundStyle(FramwiseTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)

                Text("Import footage first, then review, reject, tag, and hand off the clips worth keeping.")
                    .font(.framwiseUI(14))
                    .foregroundStyle(FramwiseTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(FramwiseTheme.surface.opacity(0.88))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(FramwiseTheme.subtleHighlight.opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 1.6, dash: [12, 8])
                                )
                                .foregroundStyle(isTargeted ? FramwiseTheme.accent : FramwiseTheme.line)
                        )
                        .frame(width: 580, height: 320)

                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(isTargeted ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised)
                            Image(systemName: "film.stack.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(isTargeted ? FramwiseTheme.accent : FramwiseTheme.warm)
                        }
                        .frame(width: 74, height: 74)

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
            }

            if importViewModel.isResolvingSources {
                FramwiseStatePanel(
                    state: .loading,
                    title: "Reading sources",
                    message: "Scanning selected files and folders before import.",
                    compact: true
                )
                .frame(maxWidth: 460)
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
                        .frame(width: 360)
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
                        .frame(width: 360)

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
                .framwisePanel(background: FramwiseTheme.surface, radius: 20)
            }

            VStack(spacing: 8) {
                if let error = importViewModel.error {
                    FramwiseStatePanel(
                        state: .error,
                        title: "Import failed",
                        message: error.localizedDescription,
                        compact: true
                    )
                    .frame(maxWidth: 460)
                }

                if !importViewModel.importWarnings.isEmpty {
                    FramwiseStatePanel(
                        state: .error,
                        title: "\(importViewModel.importWarningDisplayCount) file\(importViewModel.importWarningDisplayCount == 1 ? "" : "s") skipped",
                        message: importViewModel.importWarnings.map { "\($0.title): \($0.message)" }.prefix(2).joined(separator: "\n"),
                        systemImage: "exclamationmark.triangle.fill",
                        compact: true
                    )
                    .frame(maxWidth: 460)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FramwiseTheme.appGradient)
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
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(FramwiseTheme.surfaceRaised.opacity(0.7))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(FramwiseTheme.line.opacity(0.65), lineWidth: 1)
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

#Preview {
    DropZoneView()
        .environmentObject(AppState())
        .environmentObject(VideoImportViewModel())
        .frame(width: 600, height: 500)
}
