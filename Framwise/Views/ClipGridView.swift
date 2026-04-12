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
    @State private var scrollToClipID: UUID?
    @State private var showTimeline = true
    @State private var hoveredClip: VideoClip?
    @State private var showPreviewModal = false
    @State private var previewingClip: VideoClip?
    @State private var draggedClipID: UUID?
    @State private var dropTargetID: UUID?
    @State private var hideWasteClips = false
    @FocusState private var isGridFocused: Bool

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

                // View mode toggle
                Picker("", selection: $gridViewModel.viewMode) {
                    ForEach(ClipGridViewModel.ViewMode.allCases, id: \.self) { mode in
                        Image(systemName: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 70)
                .help("View: All / Selected clips")

                // Source filter indicator
                if let sourceURL = appState.selectedSourceURL {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(sourceURL.lastPathComponent)
                            .font(.caption)
                        Button(action: { appState.selectedSourceURL = nil }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }

                // Selected count badge
                if gridViewModel.viewMode == .selected {
                    Text("\(groupedClips.flatMap { $0.clips }.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(4)
                }

                // Reset order button (only when custom order is active)
                if appState.importSession?.userClipOrder != nil {
                    Button(action: {
                        appState.importSession?.resetClipOrder()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset Order")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                }

                // Waste filter
                let wasteCount = wasteClipCount
                if wasteCount > 0 {
                    Button(action: { hideWasteClips.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: hideWasteClips ? "eye.slash" : "eye")
                            if hideWasteClips {
                                Text("\(wasteCount) hidden")
                            }
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(hideWasteClips ? Color.red.opacity(0.15) : Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                    .help(hideWasteClips ? "Show waste clips" : "Hide waste clips")
                }

                Spacer()

                // Grid size picker
                Picker("", selection: $gridSize) {
                    ForEach(GridSize.allCases, id: \.self) { size in
                        Image(systemName: size.systemImage).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .help("Grid Size: Small / Medium / Large")

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
                        // 反选基于当前显示的片段，而不是全部片段
                        let currentClips = groupedClips.flatMap { $0.clips }
                        if !currentClips.isEmpty {
                            gridViewModel.invertSelection(currentClips, in: appState)
                        }
                    }
                } label: {
                    Image(systemName: "checkmark.circle")
                }
                .menuStyle(.borderlessButton)

                // Timeline toggle
                Button(action: { showTimeline.toggle() }) {
                    Image(systemName: "timeline.view")
                        .opacity(showTimeline ? 1.0 : 0.5)
                }
                .buttonStyle(.plain)
                .help(showTimeline ? "Hide Timeline" : "Show Timeline")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Mini Timeline Navigation
            if showTimeline && !groupedClips.isEmpty {
                CollapsedTimelineView(
                    groups: groupedClips,
                    selectedClipIDs: appState.selectedClipIDs,
                    onClipTap: { clip in
                        scrollToClipID = clip.id
                    }
                )
                Divider()
            }

            // Grid
            GeometryReader { gridGeometry in
                let availableWidth = gridGeometry.size.width - 24 // padding
                let columnCount = max(1, Int(availableWidth / (gridSize.cellSize.width + 12)))
                let columns = Array(repeating: GridItem(.fixed(gridSize.cellSize.width), spacing: 12), count: columnCount)

                ScrollViewReader { proxy in
                    ScrollView {
                        if appState.importSession?.userClipOrder != nil {
                            // Flat grid (custom order)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(orderedFlatClips) { clip in
                                    clipCell(clip)
                                }
                            }
                            .padding()
                        } else {
                            // Grouped grid (default)
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(groupedClips, id: \.sourceURL) { group in
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Section header
                                        HStack {
                                            Image(systemName: "video.fill")
                                                .foregroundColor(.accentColor)
                                            Text(group.sourceURL.lastPathComponent)
                                                .font(.headline)
                                            Text("\(group.clips.count) clips")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            if let firstClip = group.clips.first {
                                                Button("Select All") {
                                                    selectAllFromSameFile(as: firstClip)
                                                }
                                                .buttonStyle(.plain)
                                                .foregroundColor(.accentColor)
                                                .font(.caption)
                                            }
                                        }
                                        .padding(.horizontal)

                                        // Clips grid
                                        LazyVGrid(columns: columns, spacing: 12) {
                                            ForEach(group.clips) { clip in
                                                clipCell(clip)
                                            }
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                    .onChange(of: scrollToClipID) { _, newID in
                        if let clipID = newID {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(clipID, anchor: .center)
                            }
                            scrollToClipID = nil
                        }
                    }
                }
            }
        }
        .focusable()
        .onKeyPress(.space) {
            if let clip = hoveredClip {
                previewingClip = clip
                showPreviewModal = true
                return .handled
            }
            return .ignored
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
        .sheet(isPresented: $showPreviewModal) {
            if let clip = previewingClip {
                ClipPreviewModal(clip: clip, isPresented: $showPreviewModal)
            }
        }
    }

    private var filteredClips: [VideoClip] {
        guard let session = appState.importSession else { return [] }
        return gridViewModel.filteredClips(from: session.allClips, selectedIDs: appState.selectedClipIDs, sourceURL: appState.selectedSourceURL, hideWaste: hideWasteClips)
    }

    private var groupedClips: [(sourceURL: URL, clips: [VideoClip])] {
        guard let session = appState.importSession else { return [] }
        return gridViewModel.groupedClips(from: session.allClips, selectedIDs: appState.selectedClipIDs, sourceURL: appState.selectedSourceURL, hideWaste: hideWasteClips)
    }

    private var wasteClipCount: Int {
        guard let session = appState.importSession else { return 0 }
        return session.allClips.filter { $0.wasteType != .none }.count
    }

    private var orderedFlatClips: [VideoClip] {
        guard let session = appState.importSession,
              let order = session.userClipOrder else { return [] }
        let clipMap = Dictionary(uniqueKeysWithValues: session.allClips.map { ($0.id, $0) })
        return order.compactMap { clipMap[$0] }
    }

    @ViewBuilder
    private func clipCell(_ clip: VideoClip) -> some View {
        ClipCellView(
            clip: clip,
            size: gridSize.cellSize,
            isSelected: appState.selectedClipIDs.contains(clip.id),
            thumbnailGenerator: thumbnailGenerator
        )
        .id(clip.id)
        .onDrag {
            self.draggedClipID = clip.id
            return NSItemProvider(object: clip.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: ClipDropDelegate(
            targetClipID: clip.id,
            draggedClipID: $draggedClipID,
            dropTargetID: $dropTargetID,
            onMove: { draggedID, targetID in
                appState.importSession?.moveClip(draggedID, toTarget: targetID)
            }
        ))
        .overlay(
            dropTargetID == clip.id ?
            RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3) : nil
        )
        .opacity(draggedClipID == clip.id ? 0.3 : 1.0)
        .onHover { isHovering in
            if isHovering {
                hoveredClip = clip
            } else if hoveredClip?.id == clip.id {
                hoveredClip = nil
            }
        }
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
            Button("Preview") {
                previewingClip = clip
                showPreviewModal = true
            }
        }
    }

    private func selectAllFromSameFile(as referenceClip: VideoClip) {
        guard let session = appState.importSession else { return }
        let sameFileClips = session.allClips.filter { $0.sourceFileURL == referenceClip.sourceFileURL }
        for clip in sameFileClips {
            appState.selectedClipIDs.insert(clip.id)
        }
    }
}

// MARK: - Collapsed Timeline View

struct CollapsedTimelineView: View {
    let groups: [(sourceURL: URL, clips: [VideoClip])]
    let selectedClipIDs: Set<UUID>
    let onClipTap: (VideoClip) -> Void

    @State private var hoveredClipID: UUID?

    // Computed properties
    private var allClips: [VideoClip] {
        groups.flatMap { $0.clips }
    }

    private var maxTime: Double {
        max(allClips.map { CMTimeGetSeconds($0.timecodeEnd) }.max() ?? 1, 0.001)
    }

    private var fileColorMap: [URL: Color] {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint,
            .red, .yellow, .teal, .brown
        ]
        return Dictionary(uniqueKeysWithValues:
            groups.enumerated().map { ($0.element.sourceURL, colors[$0.offset % colors.count]) }
        )
    }

    var body: some View {
        if allClips.isEmpty {
            EmptyView()
        } else {
            timelineContent
        }
    }

    private var timelineContent: some View {
        TimelineGeometryReader(
            allClips: allClips,
            maxTime: maxTime,
            fileColorMap: fileColorMap,
            selectedClipIDs: selectedClipIDs,
            hoveredClipID: hoveredClipID,
            onClipTap: onClipTap,
            onHover: { clipID, hovering in
                hoveredClipID = hovering ? clipID : nil
            }
        )
        .frame(height: 24)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline navigation with \(allClips.count) clips")
    }
}

// MARK: - Timeline Geometry Reader

struct TimelineGeometryReader: View {
    let allClips: [VideoClip]
    let maxTime: Double
    let fileColorMap: [URL: Color]
    let selectedClipIDs: Set<UUID>
    let hoveredClipID: UUID?
    let onClipTap: (VideoClip) -> Void
    let onHover: (UUID, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            TimelineContent(
                allClips: allClips,
                maxTime: maxTime,
                fileColorMap: fileColorMap,
                selectedClipIDs: selectedClipIDs,
                hoveredClipID: hoveredClipID,
                width: geometry.size.width,
                onClipTap: onClipTap,
                onHover: onHover
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline with \(allClips.count) clips")
    }
}

struct TimelineContent: View {
    let allClips: [VideoClip]
    let maxTime: Double
    let fileColorMap: [URL: Color]
    let selectedClipIDs: Set<UUID>
    let hoveredClipID: UUID?
    let width: CGFloat
    let onClipTap: (VideoClip) -> Void
    let onHover: (UUID, Bool) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            // Background track
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.15))

            // Clip blocks
            Group {
                ForEach(allClips) { clip in
                    ClipBlockView(
                        clip: clip,
                        maxTime: maxTime,
                        totalWidth: width,
                        color: fileColorMap[clip.sourceFileURL] ?? .gray,
                        isSelected: selectedClipIDs.contains(clip.id),
                        isHovered: hoveredClipID == clip.id,
                        onTap: { onClipTap(clip) },
                        onHover: { hovering in
                            onHover(clip.id, hovering)
                        }
                    )
                }
            }

            // Time markers
            TimeMarkersView(totalDuration: maxTime, width: width)
        }
    }
}

// MARK: - Clip Block View

struct ClipBlockView: View {
    let clip: VideoClip
    let maxTime: Double
    let totalWidth: CGFloat
    let color: Color
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    private var startRatio: Double {
        CMTimeGetSeconds(clip.timecodeStart) / maxTime
    }

    private var endRatio: Double {
        CMTimeGetSeconds(clip.timecodeEnd) / maxTime
    }

    private var blockWidth: CGFloat {
        max((endRatio - startRatio) * totalWidth, 2)
    }

    private var xOffset: CGFloat {
        startRatio * totalWidth
    }

    private var fillColor: Color {
        if isSelected {
            return .accentColor
        } else if isHovered {
            return color.opacity(0.9)
        } else {
            return color.opacity(0.6)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fillColor)
            .frame(width: blockWidth, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isSelected ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .offset(x: xOffset)
            .onHover { hovering in
                onHover(hovering)
            }
            .onTapGesture {
                onTap()
            }
            .help("\(clip.sourceFileName): \(clip.timecodeStartString) - \(clip.timecodeEndString)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clip from \(clip.sourceFileName), \(clip.timecodeStartString) to \(clip.timecodeEndString)")
            .accessibilityHint(isSelected ? "Selected. Double-click to deselect." : "Not selected. Double-click to select.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Time Markers View

struct TimeMarkersView: View {
    let totalDuration: Double
    let width: CGFloat

    private var markerCount: Int {
        min(Int(totalDuration / 60), 6) + 1
    }

    private var interval: Double {
        totalDuration / Double(markerCount)
    }

    var body: some View {
        Group {
            ForEach(0...markerCount, id: \.self) { index in
                TimeMarkerView(
                    time: Double(index) * interval,
                    totalDuration: totalDuration,
                    width: width
                )
            }
        }
    }
}

struct TimeMarkerView: View {
    let time: Double
    let totalDuration: Double
    let width: CGFloat

    private var xPos: CGFloat {
        (time / totalDuration) * width - 15
    }

    private var timeText: String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return mins > 0 ? "\(mins):\(String(format: "%02d", secs))" : "\(secs)s"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(timeText)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 4)
        }
        .offset(x: xPos)
    }
}

// MARK: - Clip Preview Modal

struct ClipPreviewModal: View {
    let clip: VideoClip
    @Binding var isPresented: Bool

    @StateObject private var viewModel = PreviewViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.sourceFileName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(clip.timecodeStartString) - \(clip.timecodeEndString)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Video player
            ZStack {
                if let player = viewModel.player {
                    VideoPlayerView(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .background(Color.black)
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        )
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Controls
            HStack(spacing: 16) {
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: max(0, min(geometry.size.width * (viewModel.currentTime / max(viewModel.duration, 1)), geometry.size.width)), height: 4)
                            .cornerRadius(2)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                viewModel.currentTime = progress * viewModel.duration
                            }
                            .onEnded { value in
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                viewModel.seek(to: progress * viewModel.duration)
                            }
                    )
                }
                .frame(height: 20)

                Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 100)

                Button(action: { viewModel.seek(to: 0) }) {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 640, height: 480)
        .focusable()
        .onKeyPress(.space) {
            isPresented = false
            return .handled
        }
        .onAppear {
            viewModel.loadClip(clip)
            viewModel.play()  // Auto-play when modal opens
        }
        .onDisappear {
            viewModel.cleanupPlayer()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Clip Drop Delegate

struct ClipDropDelegate: DropDelegate {
    let targetClipID: UUID
    @Binding var draggedClipID: UUID?
    @Binding var dropTargetID: UUID?
    let onMove: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedClipID != nil && draggedClipID != targetClipID
    }

    func dropEntered(info: DropInfo) {
        dropTargetID = targetClipID
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetClipID {
            dropTargetID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggedClipID else { return false }
        onMove(draggedID, targetClipID)
        draggedClipID = nil
        dropTargetID = nil
        return true
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
