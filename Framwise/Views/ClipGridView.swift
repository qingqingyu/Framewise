//
//  ClipGridView.swift
//  Framwise
//
//  Grid view for browsing video clips
//

import SwiftUI
import AVFoundation

struct ClipGridView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gridViewModel: ClipGridViewModel

    // Shared thumbnail generator instance
    private let thumbnailGenerator = ThumbnailGenerator.shared

    @State private var gridSize: GridSize = .medium
    @State private var showFilterOptions = false

    enum GridSize: String, CaseIterable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"

        var cellSize: CGSize {
            switch self {
            case .small: return CGSize(width: 150, height: 100)
            case .medium: return CGSize(width: 220, height: 150)
            case .large: return CGSize(width: 320, height: 200)
            }
        }

        var columns: Int {
            switch self {
            case .small: return 6
            case .medium: return 4
            case .large: return 3
            }
        }

        var systemImage: String {
            switch self {
            case .small: return "square.grid.4x3.fill"
            case .medium: return "square.grid.3x3.fill"
            case .large: return "square.grid.2x2.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search clips...", text: $gridViewModel.searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 200)

                    if !gridViewModel.searchText.isEmpty {
                        Button(action: { gridViewModel.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

                Spacer()

                // Grid size picker
                Picker("Grid Size", selection: $gridSize) {
                    ForEach(GridSize.allCases, id: \.self) { size in
                        Image(systemName: size.systemImage).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                // Selection actions
                Menu {
                    Button("Select All") {
                        if let session = appState.importSession {
                            gridViewModel.selectAll(session.allClips, in: appState)
                        }
                    }
                    Button("Deselect All") {
                        gridViewModel.deselectAll(in: appState)
                    }
                    Button("Invert Selection") {
                        if let session = appState.importSession {
                            gridViewModel.invertSelection(session.allClips, in: appState)
                        }
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Grid
            ScrollView {
                let columns = Array(repeating: GridItem(.fixed(gridSize.cellSize.width), spacing: 12), count: gridSize.columns)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredClips) { clip in
                        ClipCellView(
                            clip: clip,
                            size: gridSize.cellSize,
                            isSelected: appState.selectedClipIDs.contains(clip.id),
                            thumbnailGenerator: thumbnailGenerator
                        )
                        .onTapGesture {
                            gridViewModel.toggleSelection(clip.id, in: appState)
                        }
                        .contextMenu {
                            Button(appState.selectedClipIDs.contains(clip.id) ? "Deselect" : "Select") {
                                gridViewModel.toggleSelection(clip.id, in: appState)
                            }
                            Divider()
                            Button("Select All from Same File") {
                                selectAllFromSameFile(as: clip)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            // 预加载缩略图
            Task {
                if let session = appState.importSession {
                    await thumbnailGenerator.preloadThumbnails(
                        for: session.allClips,
                        targetSize: gridSize.cellSize
                    )
                }
            }
        }
    }

    private var filteredClips: [VideoClip] {
        guard let session = appState.importSession else { return [] }
        return gridViewModel.filteredClips(from: session.allClips)
    }

    private func selectAllFromSameFile(as referenceClip: VideoClip) {
        guard let session = appState.importSession else { return }
        let sameFileClips = session.allClips.filter { $0.sourceFileURL == referenceClip.sourceFileURL }
        for clip in sameFileClips {
            appState.selectedClipIDs.insert(clip.id)
        }
    }
}

// MARK: - Preview

#Preview {
    let appState = AppState()
    let session = ImportSession()

    // Add some sample clips
    for i in 0..<20 {
        let clip = VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/path/to/video\(i % 3).mp4"),
            timecodeStart: CMTime(seconds: Double(i * 5), preferredTimescale: 600),
            timecodeEnd: CMTime(seconds: Double((i + 1) * 5), preferredTimescale: 600)
        )
        session.addClips([clip])
    }

    appState.importSession = session

    return ClipGridView()
        .environmentObject(appState)
        .environmentObject(ClipGridViewModel())
        .frame(width: 800, height: 600)
}
