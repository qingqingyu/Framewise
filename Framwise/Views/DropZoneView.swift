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
                VStack(spacing: 8) {
                    ProgressView(value: importViewModel.importProgress) {
                        Text(importViewModel.statusMessage)
                            .font(.caption)
                    }
                    .frame(width: 300)

                    Text("\(Int(importViewModel.importProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            importFiles(urls: urls)
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

        // 创建新的导入会话
        let session = ImportSession()
        appState.importSession = session

        Task {
            await importViewModel.importVideos(from: urls, into: session)
        }
    }
}

#Preview {
    DropZoneView()
        .environmentObject(AppState())
        .environmentObject(VideoImportViewModel())
        .frame(width: 600, height: 500)
}
