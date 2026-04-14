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
        VStack(spacing: 20) {
            Spacer()

            // Drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 3, dash: [12, 6])
                    )
                    .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                    )
                    .frame(width: 400, height: 250)

                VStack(spacing: 16) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 60))
                        .foregroundColor(isTargeted ? .accentColor : .secondary)

                    Text("Drag & Drop Video Files")
                        .font(.title2)
                        .foregroundColor(isTargeted ? .accentColor : .primary)

                    Text("or")
                        .foregroundColor(.secondary)

                    Button("Choose Files") {
                        showFileImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }

            // Supported formats
            VStack(spacing: 8) {
                Text("Supported Formats")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach(["MP4", "MOV", "MXF", "AVI", "MKV"], id: \.self) { format in
                        Text(format)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            // Import progress
            if importViewModel.isImporting {
                VStack(spacing: 12) {
                    // File progress (only show when multiple files)
                    if importViewModel.totalFilesCount > 1 {
                        VStack(spacing: 4) {
                            HStack {
                                Text("Files")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(importViewModel.importProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: importViewModel.importProgress)
                        }
                        .frame(width: 300)
                    }

                    // Analysis progress (if analyzing)
                    if importViewModel.isAnalyzing {
                        VStack(spacing: 4) {
                            HStack {
                                Text("Analyzing \(importViewModel.currentVideoName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(importViewModel.analyzingProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: importViewModel.analyzingProgress)
                                .tint(.orange)
                        }
                        .frame(width: 300)

                        // Clips found count
                        HStack {
                            Image(systemName: "film")
                                .foregroundColor(.accentColor)
                            Text("\(importViewModel.clipsFoundCount) clips found")
                                .font(.headline)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            // Error display
            if let error = importViewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let supportedExtensions = Set(["mp4", "mov", "mxf", "avi", "mkv", "m4v"])

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
                    if supportedExtensions.contains(url.pathExtension.lowercased()) {
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

        Task {
            await importViewModel.importVideosStreaming(from: urls, into: appState.importSession!)
        }
    }
}

#Preview {
    DropZoneView()
        .environmentObject(AppState())
        .environmentObject(VideoImportViewModel())
        .frame(width: 600, height: 500)
}
