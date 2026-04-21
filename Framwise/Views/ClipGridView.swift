//
//  ClipGridView.swift
//  Framwise
//
//  Grid view for browsing video clips
//

import SwiftUI
import AppKit
import AVFoundation

struct ClipGridView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var gridViewModel: ClipGridViewModel

    // Shared thumbnail generator instance
    private let thumbnailGenerator = ThumbnailGenerator.shared

    @State private var gridSize: GridSize = .medium
    @State private var scrollToClipID: UUID?
    @State private var showTimeline = true
    @State private var hoveredClip: VideoClip?
    @State private var showPreviewModal = false
    @State private var previewingClip: VideoClip?
    @State private var draggedClipID: UUID?
    @State private var dropTargetID: UUID?
    @State private var hideWasteClips = false
    @State private var showCreateTag = false
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
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(FramwiseTheme.textMuted)
                        TextField("Search clips, vows, reactions...", text: $gridViewModel.searchText)
                            .textFieldStyle(.plain)
                            .font(.framwiseUI(13))
                            .foregroundStyle(FramwiseTheme.textPrimary)

                        if !gridViewModel.searchText.isEmpty {
                            Button(action: { gridViewModel.searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(FramwiseTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 999)
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 380)

                    HStack(spacing: 6) {
                        ForEach(ClipGridViewModel.ViewMode.allCases, id: \.self) { mode in
                            modeChip(
                                title: mode.rawValue,
                                systemImage: mode.systemImage,
                                isSelected: gridViewModel.viewMode == mode
                            ) {
                                gridViewModel.viewMode = mode
                            }
                        }
                    }
                    .padding(4)
                    .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 999)

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(GridSize.allCases, id: \.self) { size in
                            modeChip(
                                title: size.rawValue,
                                systemImage: size.systemImage,
                                isSelected: gridSize == size
                            ) {
                                gridSize = size
                            }
                        }
                    }
                    .padding(4)
                    .framwisePanel(background: FramwiseTheme.surfaceRaised, radius: 999)

                    Menu {
                        Button("Select All") {
                            let currentClips = groupedClips.flatMap { $0.clips }
                            if !currentClips.isEmpty {
                                gridViewModel.selectAll(currentClips, in: appState)
                            }
                        }
                        Button("Deselect All") {
                            gridViewModel.deselectAll(in: appState)
                        }
                        Button("Invert Selection") {
                            let currentClips = groupedClips.flatMap { $0.clips }
                            if !currentClips.isEmpty {
                                gridViewModel.invertSelection(currentClips, in: appState)
                            }
                        }
                    } label: {
                        Label("Selection", systemImage: "checkmark.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(FramwiseGhostButtonStyle())

                    Button(action: { showTimeline.toggle() }) {
                        Label(showTimeline ? "Timeline On" : "Timeline Off", systemImage: "timeline.view")
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: showTimeline ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised,
                        border: showTimeline ? FramwiseTheme.accent.opacity(0.35) : FramwiseTheme.line.opacity(0.8),
                        foreground: showTimeline ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted
                    ))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let sourceURL = appState.selectedSourceURL {
                            filterChip(
                                title: sourceURL.lastPathComponent,
                                systemImage: "line.3.horizontal.decrease.circle.fill",
                                fill: FramwiseTheme.accentSoft,
                                border: FramwiseTheme.accent.opacity(0.28),
                                foreground: FramwiseTheme.textPrimary
                            ) {
                                appState.selectedSourceURL = nil
                            }
                        }

                        if let tagFilterID = appState.importSession?.activeTagFilter,
                           let tag = appState.importSession?.tags.first(where: { $0.id == tagFilterID }) {
                            filterChip(
                                title: tag.name,
                                dotColor: tag.color.systemColor,
                                fill: tag.color.systemColor.opacity(0.16),
                                border: tag.color.systemColor.opacity(0.28),
                                foreground: FramwiseTheme.textPrimary
                            ) {
                                appState.importSession?.activeTagFilter = nil
                            }
                        }

                        if gridViewModel.viewMode == .selected {
                            passiveChip(title: "\(groupedClips.flatMap { $0.clips }.count) in selection", systemImage: "checkmark.circle.fill")
                        }

                        if appState.importSession?.userClipOrder != nil {
                            Button(action: {
                                appState.importSession?.resetClipOrder()
                            }) {
                                Label("Reset Order", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(FramwiseGhostButtonStyle(
                                fill: FramwiseTheme.surfaceRaised,
                                border: FramwiseTheme.accent.opacity(0.28),
                                foreground: FramwiseTheme.textPrimary
                            ))
                        }

                        if wasteClipCount > 0 {
                            Button(action: { hideWasteClips.toggle() }) {
                                Label(
                                    hideWasteClips ? "\(wasteClipCount) hidden" : "Hide waste",
                                    systemImage: hideWasteClips ? "eye.slash.fill" : "eye.fill"
                                )
                            }
                            .buttonStyle(FramwiseGhostButtonStyle(
                                fill: hideWasteClips ? FramwiseTheme.danger.opacity(0.14) : FramwiseTheme.surfaceRaised,
                                border: hideWasteClips ? FramwiseTheme.danger.opacity(0.28) : FramwiseTheme.line.opacity(0.8),
                                foreground: hideWasteClips ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted
                            ))
                        }

                        if similarityGroupCount > 0 {
                            Button(action: {
                                gridViewModel.groupSimilar.toggle()
                                if !gridViewModel.groupSimilar {
                                    gridViewModel.similarityGroupFilter = nil
                                }
                            }) {
                                Label(
                                    gridViewModel.groupSimilar ? "\(similarityGroupCount) groups" : "Group similar",
                                    systemImage: "square.on.square"
                                )
                            }
                            .buttonStyle(FramwiseGhostButtonStyle(
                                fill: gridViewModel.groupSimilar ? FramwiseTheme.info.opacity(0.14) : FramwiseTheme.surfaceRaised,
                                border: gridViewModel.groupSimilar ? FramwiseTheme.info.opacity(0.28) : FramwiseTheme.line.opacity(0.8),
                                foreground: gridViewModel.groupSimilar ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted
                            ))
                        }

                        if let groupFilter = gridViewModel.similarityGroupFilter {
                            filterChip(
                                title: similarityGroupLabel(for: groupFilter),
                                systemImage: "square.on.square.fill",
                                fill: FramwiseTheme.info.opacity(0.16),
                                border: FramwiseTheme.info.opacity(0.28),
                                foreground: FramwiseTheme.textPrimary
                            ) {
                                gridViewModel.similarityGroupFilter = nil
                            }
                        }
                    }
                }
            }
            .padding(16)
            .framwisePanel(background: FramwiseTheme.surface, radius: 22)

            if showTimeline && !groupedClips.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SEQUENCE MAP")
                                .font(.framwiseMono(10))
                                .foregroundStyle(FramwiseTheme.warm)
                            Text(groupsSummary)
                                .font(.framwiseUI(13, weight: .medium))
                                .foregroundStyle(FramwiseTheme.textPrimary)
                        }
                        Spacer()
                        passiveChip(
                            title: groupedClips.count > 1 ? "\(groupedClips.count) sources" : "1 source",
                            systemImage: "timeline.selection"
                        )
                    }

                    CollapsedTimelineView(
                        groups: groupedClips,
                        selectedClipIDs: appState.selectedClipIDs,
                        onClipTap: { clip in
                            scrollToClipID = clip.id
                        }
                    )
                }
                .padding(16)
                .framwisePanel(background: FramwiseTheme.surface, radius: 20)
            }

            GeometryReader { gridGeometry in
                let availableWidth = gridGeometry.size.width - 24
                let columnCount = max(1, Int(availableWidth / (gridSize.cellSize.width + 12)))
                let columns = Array(repeating: GridItem(.fixed(gridSize.cellSize.width), spacing: 12), count: columnCount)

                ScrollViewReader { proxy in
                    ScrollView {
                        if visibleClipsInDisplayOrder.isEmpty {
                            emptyResultsView
                                .padding(28)
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else if appState.importSession?.userClipOrder != nil {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(orderedFlatClips) { clip in
                                    clipCell(clip)
                                }
                            }
                            .padding()
                        } else {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(groupedClips, id: \.sourceURL) { group in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(group.sourceURL.lastPathComponent)
                                                    .font(.framwiseDisplay(18, weight: .semibold))
                                                    .foregroundStyle(FramwiseTheme.textPrimary)
                                                Text("\(group.clips.count) clips")
                                                    .font(.framwiseMono(11))
                                                    .foregroundStyle(FramwiseTheme.textMuted)
                                            }

                                            Spacer()

                                            Text(group.sourceURL.deletingPathExtension().lastPathComponent.uppercased())
                                                .font(.framwiseMono(10))
                                                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.75))
                                                .lineLimit(1)
                                                .frame(maxWidth: 200, alignment: .trailing)

                                            if let firstClip = group.clips.first {
                                                Button(action: {
                                                    selectAllFromSameFile(as: firstClip)
                                                }) {
                                                    Label("Select All", systemImage: "checkmark.circle.fill")
                                                }
                                                .buttonStyle(FramwiseGhostButtonStyle(
                                                    fill: FramwiseTheme.surfaceRaised,
                                                    border: FramwiseTheme.line.opacity(0.8),
                                                    foreground: FramwiseTheme.textPrimary
                                                ))
                                            }
                                        }
                                        .padding(.horizontal, 2)

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
                    .background(Color.clear)
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
            .framwisePanel(background: FramwiseTheme.surface, radius: 22)
        }
        .padding(16)
        .background(FramwiseTheme.appGradient)
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
        .sheet(isPresented: $showCreateTag) {
            TagCreateView(
                existingNames: Set(appState.importSession?.tags.map(\.name) ?? [])
            ) { tag in
                appState.importSession?.addTag(tag) ?? false
            }
        }
    }

    @ViewBuilder
    private func filterChip(
        title: String,
        systemImage: String? = nil,
        dotColor: Color? = nil,
        fill: Color,
        border: Color,
        foreground: Color,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .font(.framwiseUI(12, weight: .medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(fill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func passiveChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
        }
        .font(.framwiseUI(12, weight: .medium))
        .foregroundStyle(FramwiseTheme.textMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(FramwiseTheme.surfaceRaised)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(FramwiseTheme.line.opacity(0.8), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func modeChip(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
            }
            .font(.framwiseUI(12, weight: .medium))
            .foregroundStyle(isSelected ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? FramwiseTheme.accentSoft : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? FramwiseTheme.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 14) {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "film.stack")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.85))

            Text(hasActiveFilters ? "No Clips Match Current Filters" : "No Clips In View")
                .font(.framwiseDisplay(24, weight: .semibold))
                .foregroundStyle(FramwiseTheme.textPrimary)

            Text(emptyResultsExplanation)
                .font(.framwiseUI(13))
                .foregroundStyle(FramwiseTheme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if hasActiveFilters {
                Button("Clear Filters") {
                    gridViewModel.searchText = ""
                    appState.selectedSourceURL = nil
                    appState.importSession?.activeTagFilter = nil
                    hideWasteClips = false
                    gridViewModel.viewMode = .all
                }
                .buttonStyle(FramwisePrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .framwisePanel(background: FramwiseTheme.surface, radius: 24)
    }

    private var filteredClips: [VideoClip] {
        guard let session = appState.importSession else { return [] }
        return gridViewModel.filteredClips(from: session.allClips, selectedIDs: appState.selectedClipIDs, sourceURL: appState.selectedSourceURL, tagFilter: session.activeTagFilter, hideWaste: hideWasteClips)
    }

    private var groupedClips: [(sourceURL: URL, clips: [VideoClip])] {
        guard let session = appState.importSession else { return [] }
        return gridViewModel.groupedClips(from: session.allClips, selectedIDs: appState.selectedClipIDs, sourceURL: appState.selectedSourceURL, tagFilter: session.activeTagFilter, hideWaste: hideWasteClips)
    }

    private var wasteClipCount: Int {
        guard let session = appState.importSession else { return 0 }
        return session.allClips.filter { $0.wasteType != .none }.count
    }

    private var similarityGroupCount: Int {
        appState.importSession?.similarityGroups.count ?? 0
    }

    private var similarityGroupSizeMap: [UUID: Int] {
        guard let groups = appState.importSession?.similarityGroups else { return [:] }
        return Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.count) })
    }

    private func similarityGroupLabel(for groupID: UUID) -> String {
        if let group = appState.importSession?.similarityGroups.first(where: { $0.id == groupID }) {
            return "\(group.count) takes"
        }
        return "Group"
    }

    private var hasActiveFilters: Bool {
        !gridViewModel.searchText.isEmpty ||
        appState.selectedSourceURL != nil ||
        appState.importSession?.activeTagFilter != nil ||
        hideWasteClips ||
        gridViewModel.viewMode != .all ||
        gridViewModel.similarityGroupFilter != nil
    }

    private var emptyResultsExplanation: String {
        if !gridViewModel.searchText.isEmpty {
            return "Try loosening the search phrase or clearing the active chips to bring clips back into the light table."
        }
        if hasActiveFilters {
            return "Current source, tag, selection, or waste filters are hiding every clip in this workspace."
        }
        return "This view does not have any clips to show yet."
    }

    private var groupsSummary: String {
        let clipCount = groupedClips.flatMap(\.clips).count
        if groupedClips.count > 1 {
            return "\(clipCount) clips across active sources"
        }
        return "\(clipCount) clips on current reel"
    }

    private var visibleClipsInDisplayOrder: [VideoClip] {
        if appState.importSession?.userClipOrder != nil {
            return orderedFlatClips
        }
        return groupedClips.flatMap(\.clips)
    }

    /// Clips in user's custom order, with all filters (search/tag/source/viewMode/waste) applied
    private var orderedFlatClips: [VideoClip] {
        guard let session = appState.importSession,
              let order = session.userClipOrder else { return [] }
        // Apply the same filters as groupedClips via gridViewModel
        let filteredSet = Set(filteredClips.map { $0.id })
        let clipMap = Dictionary(uniqueKeysWithValues: session.allClips.map { ($0.id, $0) })
        return order.compactMap { id in
            filteredSet.contains(id) ? clipMap[id] : nil
        }
    }

    @ViewBuilder
    private func clipCell(_ clip: VideoClip) -> some View {
        ClipCellView(
            clip: clip,
            size: gridSize.cellSize,
            isSelected: appState.selectedClipIDs.contains(clip.id),
            thumbnailGenerator: thumbnailGenerator,
            tags: appState.importSession?.tags ?? [],
            similarityGroupSize: clip.similarityGroupID.flatMap { similarityGroupSizeMap[$0] } ?? 0
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FramwiseTheme.accent, lineWidth: 3) : nil
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
            let modifiers = NSEvent.modifierFlags
            gridViewModel.handleSelection(
                clip.id,
                visibleClipIDs: visibleClipsInDisplayOrder.map(\.id),
                in: appState,
                extendRangeSelection: modifiers.contains(.shift)
            )
        }
        .contextMenu {
            Button(appState.selectedClipIDs.contains(clip.id) ? "Deselect" : "Select") {
                gridViewModel.toggleSelection(clip.id, in: appState)
            }
            Divider()
            Button("Select All from Same File") {
                selectAllFromSameFile(as: clip)
            }
            if let groupID = clip.similarityGroupID, similarityGroupSizeMap[groupID] ?? 0 >= 2 {
                Button("Show Similar Takes") {
                    gridViewModel.groupSimilar = true
                    gridViewModel.similarityGroupFilter = groupID
                }
            }
            Button("Preview") {
                previewingClip = clip
                showPreviewModal = true
            }
            Divider()

            // Assign Tag submenu
            if let session = appState.importSession {
                Menu("Assign Tag") {
                    ForEach(session.tags) { tag in
                        Button(action: {
                            assignTagToTarget(tag.id, clipID: clip.id)
                        }) {
                            HStack {
                                Circle()
                                    .fill(tag.color.systemColor)
                                    .frame(width: 8, height: 8)
                                Text(tag.name)
                                if clip.tagIDs.contains(tag.id) {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    if !session.tags.isEmpty {
                        Divider()
                    }
                    Button("New Tag...") {
                        showCreateTag = true
                    }
                }

                // Remove Tag submenu
                let clipTags = session.tags.filter { clip.tagIDs.contains($0.id) }
                if !clipTags.isEmpty {
                    Menu("Remove Tag") {
                        ForEach(clipTags) { tag in
                            Button(action: {
                                removeTagFromTarget(tag.id, clipID: clip.id)
                            }) {
                                HStack {
                                    Circle()
                                        .fill(tag.color.systemColor)
                                        .frame(width: 8, height: 8)
                                    Text(tag.name)
                                }
                            }
                        }
                    }
                }

                // Select All with Tag
                if !clipTags.isEmpty {
                    Menu("Select All with Tag") {
                        ForEach(clipTags) { tag in
                            Button(action: {
                                selectAllWithTag(tag.id)
                            }) {
                                HStack {
                                    Circle()
                                        .fill(tag.color.systemColor)
                                        .frame(width: 8, height: 8)
                                    Text(tag.name)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func selectAllFromSameFile(as referenceClip: VideoClip) {
        guard let session = appState.importSession else { return }
        for clip in session.allClips where clip.sourceFileURL == referenceClip.sourceFileURL {
            appState.selectedClipIDs.insert(clip.id)
        }
    }

    private func assignTagToTarget(_ tagID: UUID, clipID: UUID) {
        guard let session = appState.importSession else { return }
        if appState.selectedClipIDs.count > 1 && appState.selectedClipIDs.contains(clipID) {
            session.assignTag(tagID, toClipIDs: appState.selectedClipIDs)
        } else {
            session.assignTag(tagID, to: clipID)
        }
    }

    private func removeTagFromTarget(_ tagID: UUID, clipID: UUID) {
        guard let session = appState.importSession else { return }
        if appState.selectedClipIDs.count > 1 && appState.selectedClipIDs.contains(clipID) {
            session.removeTag(tagID, fromClipIDs: appState.selectedClipIDs)
        } else {
            session.removeTag(tagID, from: clipID)
        }
    }

    private func selectAllWithTag(_ tagID: UUID) {
        guard let session = appState.importSession else { return }
        let clipsWithTag = session.clipsWithTag(tagID)
        for clip in clipsWithTag {
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

    private var fileColorMap: [URL: Color] {
        let colors: [Color] = [
            FramwiseTheme.info,
            FramwiseTheme.success,
            FramwiseTheme.warning,
            FramwiseTheme.accent,
            Color(hex: "E58ACF"),
            Color(hex: "58C7D1"),
            Color(hex: "8EA6FF"),
            Color(hex: "7DDDB8"),
            FramwiseTheme.danger,
            FramwiseTheme.warm,
            Color(hex: "4FA89B"),
            Color(hex: "A77A5B")
        ]
        return Dictionary(uniqueKeysWithValues:
            groups.enumerated().map { ($0.element.sourceURL, colors[$0.offset % colors.count]) }
        )
    }

    var body: some View {
        if allClips.isEmpty {
            EmptyView()
        } else if groups.count <= 1 {
            // Single source: use original single-track layout
            singleTrackContent
        } else {
            // Multi-source: stack per-source tracks
            multiTrackContent
        }
    }

    // MARK: - Single Track (1 source)

    private var maxTime: Double {
        max(allClips.map { CMTimeGetSeconds($0.timecodeEnd) }.max() ?? 1, 0.001)
    }

    private var singleTrackContent: some View {
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
        .padding(.vertical, 10)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline navigation with \(allClips.count) clips")
    }

    // MARK: - Multi Track (per-source)

    private var multiTrackContent: some View {
        VStack(spacing: 8) {
            ForEach(groups, id: \.sourceURL) { group in
                let groupMaxTime = max(group.clips.map { CMTimeGetSeconds($0.timecodeEnd) }.max() ?? 1, 0.001)
                HStack(spacing: 10) {
                    Text(group.sourceURL.deletingPathExtension().lastPathComponent.uppercased())
                        .font(.framwiseMono(9))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(width: 120, alignment: .leading)
                        .background(
                            Capsule(style: .continuous)
                                .fill(FramwiseTheme.surfaceRaised)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(FramwiseTheme.line.opacity(0.7), lineWidth: 1)
                        )

                    TimelineGeometryReader(
                        allClips: group.clips,
                        maxTime: groupMaxTime,
                        fileColorMap: fileColorMap,
                        selectedClipIDs: selectedClipIDs,
                        hoveredClipID: hoveredClipID,
                        onClipTap: onClipTap,
                        onHover: { clipID, hovering in
                            hoveredClipID = hovering ? clipID : nil
                        }
                    )
                    .frame(height: 18)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline navigation with \(allClips.count) clips from \(groups.count) sources")
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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FramwiseTheme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(FramwiseTheme.line.opacity(0.55), lineWidth: 1)
                )

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
            return FramwiseTheme.accent
        } else if isHovered {
            return color.opacity(0.9)
        } else {
            return color.opacity(0.6)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fillColor)
            .frame(width: blockWidth, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? FramwiseTheme.warm.opacity(0.7) : Color.clear, lineWidth: 1)
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
                .font(.framwiseMono(8))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.75))
            Rectangle()
                .fill(FramwiseTheme.line.opacity(0.8))
                .frame(width: 1, height: 4)
        }
        .offset(x: xPos)
    }
}

// MARK: - Clip Preview Modal

struct ClipPreviewModal: View {
    @EnvironmentObject var appState: AppState
    let clip: VideoClip
    @Binding var isPresented: Bool

    @StateObject private var viewModel = PreviewViewModel()

    private var liveClip: VideoClip {
        appState.importSession?.allClips.first(where: { $0.id == clip.id }) ?? clip
    }

    private var clipTags: [ClipTag] {
        (appState.importSession?.tags ?? []).filter { liveClip.tagIDs.contains($0.id) }
    }

    private var isSelected: Bool {
        appState.selectedClipIDs.contains(clip.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PREVIEW MONITOR")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.warm)
                    Text(clip.sourceFileName)
                        .font(.framwiseDisplay(24, weight: .semibold))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(clip.timecodeStartString) - \(clip.timecodeEndString)")
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }
                Spacer()
                Button(action: {
                    viewModel.cleanupPlayer()
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(FramwiseGhostButtonStyle(
                    fill: FramwiseTheme.surfaceRaised,
                    border: FramwiseTheme.line.opacity(0.8),
                    foreground: FramwiseTheme.textMuted
                ))
                .keyboardShortcut(.escape, modifiers: [])
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(FramwiseTheme.line.opacity(0.8), lineWidth: 1)
                    )

                if let error = viewModel.error {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(FramwiseTheme.warning)
                        Text(error.localizedDescription)
                            .font(.framwiseUI(13))
                            .foregroundStyle(FramwiseTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else if let player = viewModel.player {
                    VideoPlayerView(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    FramwiseLoadingIndicator(tint: FramwiseTheme.warm, diameter: 28)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: { viewModel.togglePlayPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: FramwiseTheme.accentSoft,
                        border: FramwiseTheme.accent.opacity(0.35),
                        foreground: FramwiseTheme.textPrimary
                    ))

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(FramwiseTheme.surfaceRaised)
                                .frame(height: 6)

                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [FramwiseTheme.accent, FramwiseTheme.warm.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, min(geometry.size.width * (viewModel.currentTime / max(viewModel.duration, 1)), geometry.size.width)), height: 6)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    let targetTime = progress * viewModel.duration
                                    viewModel.currentTime = targetTime
                                    viewModel.seek(to: targetTime)
                                }
                                .onEnded { value in
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    viewModel.seek(to: progress * viewModel.duration)
                                }
                        )
                    }
                    .frame(height: 20)

                    Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .frame(width: 110, alignment: .trailing)

                    Button(action: { viewModel.seek(to: 0) }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(FramwiseGhostButtonStyle())
                }

                HStack(spacing: 12) {
                    FramwiseMetricBadge(title: "IN", value: clip.timecodeStartString, color: FramwiseTheme.textPrimary)
                    FramwiseMetricBadge(title: "OUT", value: clip.timecodeEndString, color: FramwiseTheme.textPrimary)
                    FramwiseMetricBadge(title: "DURATION", value: clip.durationString, color: FramwiseTheme.textPrimary)
                }

                HStack(spacing: 10) {
                    Button(action: toggleSelection) {
                        Label(
                            isSelected ? "Selected" : "Add to Selection",
                            systemImage: isSelected ? "checkmark.circle.fill" : "plus.circle"
                        )
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: isSelected ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised,
                        border: isSelected ? FramwiseTheme.accent.opacity(0.35) : FramwiseTheme.line.opacity(0.8),
                        foreground: isSelected ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted
                    ))

                    if liveClip.wasteType != .none {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(FramwiseTheme.danger)
                                .frame(width: 8, height: 8)
                            Text(liveClip.wasteType.rawValue.uppercased())
                                .font(.framwiseMono(10))
                                .foregroundStyle(FramwiseTheme.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(FramwiseTheme.danger.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(FramwiseTheme.danger.opacity(0.28), lineWidth: 1)
                        )
                    }

                    Spacer()

                    Text("SPACE play/pause  ·  ESC close")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }

                if !clipTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(clipTags) { tag in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(tag.color.systemColor)
                                        .frame(width: 8, height: 8)
                                    Text(tag.name)
                                        .lineLimit(1)
                                }
                                .font(.framwiseUI(12, weight: .medium))
                                .foregroundStyle(FramwiseTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(tag.color.systemColor.opacity(0.14))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(tag.color.systemColor.opacity(0.28), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
            .framwisePanel(background: FramwiseTheme.surface, radius: 20)
        }
        .padding(20)
        .frame(width: 760, height: 560)
        .background(FramwiseTheme.background)
        .focusable()
        .onKeyPress(.space) {
            viewModel.togglePlayPause()
            return .handled
        }
        .onAppear {
            viewModel.loadClip(clip)
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

    private func toggleSelection() {
        if isSelected {
            appState.selectedClipIDs.remove(clip.id)
        } else {
            appState.selectedClipIDs.insert(clip.id)
        }
        appState.updatePreviewFromSelection()
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
