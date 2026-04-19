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
                Text("DIGITAL LIGHT TABLE")
                    .font(.framwiseMono(11))
                    .foregroundStyle(FramwiseTheme.warm)

                VStack(spacing: 12) {
                    Text("Import footage, then\nstart making judgments.")
                        .font(.framwiseDisplay(42, weight: .semibold))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Framwise is built for the fast pass before the real edit: ingest, split, scan, reject, tag, and hand off only the clips worth touching.")
                        .font(.framwiseUI(15))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                }

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
                            Text(isTargeted ? "Release to Import" : "Drop Video Files")
                                .font(.framwiseDisplay(26, weight: .semibold))
                                .foregroundStyle(FramwiseTheme.textPrimary)

                            Text("Supports MOV, MP4, MPEG4, and QuickTime footage. Multiple reels are fine.")
                                .font(.framwiseUI(13))
                                .foregroundStyle(FramwiseTheme.textMuted)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 10) {
                            Button(action: { showFileImporter = true }) {
                                Label("Choose Files", systemImage: "plus")
                            }
                            .buttonStyle(FramwisePrimaryButtonStyle())

                            Text("or drag them straight into the bay")
                                .font(.framwiseUI(13))
                                .foregroundStyle(FramwiseTheme.textMuted)
                        }
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }

            HStack(spacing: 12) {
                ForEach(["MOV", "MP4", "MPEG4", "QuickTime"], id: \.self) { format in
                    Text(format)
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(FramwiseTheme.surfaceRaised)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(FramwiseTheme.line.opacity(0.7), lineWidth: 1)
                        )
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
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result)
        }
    }

    // MARK: - File Handling

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
                importFiles(urls: urls)
            } else if !unsupportedNames.isEmpty {
                // Only show error when ALL dropped files are unsupported
                importViewModel.error = ImportError.unsupportedFormat(unsupportedNames.joined(separator: ", "))
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

        // 如果没有session，创建新的（与 ContentView 保持一致）
        if appState.importSession == nil {
            appState.importSession = ImportSession()
        }

        importViewModel.importVideosStreaming(from: urls, into: appState.importSession!)
    }
}

#Preview {
    DropZoneView()
        .environmentObject(AppState())
        .environmentObject(VideoImportViewModel())
        .frame(width: 600, height: 500)
}
