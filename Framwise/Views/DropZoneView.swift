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

                        VStack(spacing: 8) {
                            Text(isTargeted ? "Release to import" : "Drop here to import")
                                .font(.framwiseDisplay(24, weight: .semibold))
                                .foregroundStyle(FramwiseTheme.textPrimary)

                            Text("MOV · MP4 · MPEG4 · QuickTime · folders scanned recursively")
                                .font(.framwiseUI(13))
                                .foregroundStyle(FramwiseTheme.textMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 480)
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

            if importViewModel.isImporting {
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

            if let error = importViewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(FramwiseTheme.danger)
                    Text(error.localizedDescription)
                        .font(.framwiseUI(12))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FramwiseTheme.danger.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FramwiseTheme.danger.opacity(0.22), lineWidth: 1)
                )
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
                importFiles(urls: videoURLs)
            } else if !unsupported.isEmpty {
                importViewModel.error = ImportError.unsupportedFormat(unsupported.joined(separator: ", "))
            } else {
                importViewModel.error = ImportError.noSupportedVideos
            }
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let (videoURLs, unsupported) = FileResolver.resolveVideoURLs(from: urls)
            if !videoURLs.isEmpty {
                importFiles(urls: videoURLs)
            } else if !unsupported.isEmpty {
                importViewModel.error = ImportError.unsupportedFormat(unsupported.joined(separator: ", "))
            } else {
                importViewModel.error = ImportError.noSupportedVideos
            }
        case .failure(let error):
            importViewModel.error = error
        }
    }

    private func importFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        appState.ensureSession()
        importViewModel.importVideosStreaming(from: urls, into: appState.importSession!)
    }
}

#Preview {
    DropZoneView()
        .environmentObject(AppState())
        .environmentObject(VideoImportViewModel())
        .frame(width: 600, height: 500)
}
