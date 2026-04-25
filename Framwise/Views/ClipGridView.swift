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
    @State private var focusedClipID: UUID?
    @State private var columnCount: Int = 4
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
        gridContent
        .padding(16)
        .background(FramwiseTheme.appGradient)
        .focusable()
        .onKeyPress(.space) { handleSpaceKey() }
        .onKeyPress(characters: .init(charactersIn: "123456789")) { handleTagShortcut($0) }
        .onKeyPress(.leftArrow) { moveFocus(.left) }
        .onKeyPress(.rightArrow) { moveFocus(.right) }
        .onKeyPress(.upArrow) { moveFocus(.up) }
        .onKeyPress(.downArrow) { moveFocus(.down) }
        .onKeyPress(.return) { handleEnterKey() }
        .onKeyPress(.escape) { handleEscapeKey() }
        .onChange(of: visibleClipIDs) { _, newIDs in
            if let focused = focusedClipID, !newIDs.contains(focused) {
                focusedClipID = nil
            }
            if let hovered = hoveredClip, !newIDs.contains(hovered.id) {
                hoveredClip = nil
            }
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

    private var gridContent: some View {
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
                            guard let session = appState.importSession else { return }
                            let pool = gridViewModel.clipsForInversion(
                                from: session.allClips,
                                sourceURL: appState.selectedSourceURL,
                                tagFilter: session.activeTagFilter,
                                hideWaste: hideWasteClips
                            )
                            if !pool.isEmpty {
                                gridViewModel.invertSelection(pool, in: appState)
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
                let cols = max(1, Int(availableWidth / (gridSize.cellSize.width + 12)))
                let columns = Array(repeating: GridItem(.fixed(gridSize.cellSize.width), spacing: 12), count: cols)

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

                                            if !group.clips.isEmpty {
                                                Button(action: {
                                                    selectVisibleClips(group.clips)
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
                .onAppear { columnCount = cols }
                .onChange(of: gridGeometry.size) { _, _ in
                    columnCount = max(1, Int((gridGeometry.size.width - 24) / (gridSize.cellSize.width + 12)))
                }
                .onChange(of: gridSize) { _, _ in
                    columnCount = max(1, Int((gridGeometry.size.width - 24) / (gridSize.cellSize.width + 12)))
                }
            }
            .framwisePanel(background: FramwiseTheme.surface, radius: 22)
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
        return session.allClips.filter { $0.effectiveWasteType != .none }.count
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

    private var visibleClipIDs: Set<UUID> {
        Set(visibleClipsInDisplayOrder.map(\.id))
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
        .overlay(
            focusedClipID == clip.id ?
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FramwiseTheme.warm, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
            : nil
        )
        .shadow(color: focusedClipID == clip.id ? FramwiseTheme.warm.opacity(0.3) : .clear, radius: 6)
        .opacity(draggedClipID == clip.id ? 0.3 : 1.0)
        .onHover { isHovering in
            if isHovering {
                hoveredClip = clip
            } else if hoveredClip?.id == clip.id {
                hoveredClip = nil
            }
        }
        .onTapGesture {
            focusedClipID = clip.id
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
                selectVisibleClipsFromSameFile(as: clip)
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

            // Waste override — batch operations filter to applicable clips only
            let targetIDs: Set<UUID> = appState.selectedClipIDs.contains(clip.id) && appState.selectedClipIDs.count > 1
                ? appState.selectedClipIDs
                : [clip.id]
            let isBatch = targetIDs.count > 1

            if clip.effectiveWasteType != .none {
                Button(isBatch ? "Mark \(targetIDs.count) as Non-Waste" : "Mark as Non-Waste") {
                    guard let session = appState.importSession else { return }
                    let applicable = targetIDs.filter { id in
                        session.allClips.first { $0.id == id }?.effectiveWasteType != .none
                    }
                    session.setWasteOverride(Set(applicable), override: .none)
                }
            } else if clip.wasteType == .none && !clip.isWasteOverridden {
                Button(isBatch ? "Mark \(targetIDs.count) as Waste" : "Mark as Waste") {
                    guard let session = appState.importSession else { return }
                    let applicable = targetIDs.filter { id in
                        session.allClips.first { $0.id == id }?.effectiveWasteType == .none
                    }
                    session.setWasteOverride(Set(applicable), override: .solid)
                }
            }
            if clip.isWasteOverridden {
                Button(isBatch ? "Reset \(targetIDs.count) to Auto-detected" : "Reset to Auto-detected") {
                    guard let session = appState.importSession else { return }
                    let applicable = targetIDs.filter { id in
                        session.allClips.first { $0.id == id }?.isWasteOverridden == true
                    }
                    session.setWasteOverride(Set(applicable), override: nil)
                }
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

    private func selectVisibleClips(_ clips: [VideoClip]) {
        for clip in clips {
            appState.selectedClipIDs.insert(clip.id)
        }
    }

    private func selectVisibleClipsFromSameFile(as referenceClip: VideoClip) {
        let clips = visibleClipsInDisplayOrder.filter { $0.sourceFileURL == referenceClip.sourceFileURL }
        selectVisibleClips(clips)
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

    // MARK: - Keyboard Navigation

    private enum FocusDirection { case left, right, up, down }

    private func moveFocus(_ direction: FocusDirection) -> KeyPress.Result {
        let clips = visibleClipsInDisplayOrder
        guard !clips.isEmpty else { return .ignored }

        guard let currentID = focusedClipID,
              let currentIndex = clips.firstIndex(where: { $0.id == currentID }) else {
            focusedClipID = clips.first?.id
            scrollToClipID = focusedClipID
            return .handled
        }

        let newIndex: Int
        switch direction {
        case .left:  newIndex = max(0, currentIndex - 1)
        case .right: newIndex = min(clips.count - 1, currentIndex + 1)
        case .up:    newIndex = max(0, currentIndex - columnCount)
        case .down:  newIndex = min(clips.count - 1, currentIndex + columnCount)
        }

        guard newIndex != currentIndex else { return .handled }

        withAnimation(.easeInOut(duration: 0.15)) {
            focusedClipID = clips[newIndex].id
        }
        scrollToClipID = focusedClipID
        return .handled
    }

    private func handleEnterKey() -> KeyPress.Result {
        guard let id = focusedClipID,
              let clip = visibleClipsInDisplayOrder.first(where: { $0.id == id }) else {
            return .ignored
        }
        previewingClip = clip
        showPreviewModal = true
        return .handled
    }

    private func handleEscapeKey() -> KeyPress.Result {
        if focusedClipID != nil {
            focusedClipID = nil
            return .handled
        }
        return .ignored
    }

    private func handleSpaceKey() -> KeyPress.Result {
        let targetClip: VideoClip?
        if let focused = focusedClipID {
            targetClip = visibleClipsInDisplayOrder.first { $0.id == focused }
        } else if let hovered = hoveredClip, visibleClipIDs.contains(hovered.id) {
            targetClip = hovered
        } else {
            targetClip = nil
        }
        guard let clip = targetClip else { return .ignored }
        previewingClip = clip
        showPreviewModal = true
        return .handled
    }

    private func handleTagShortcut(_ press: KeyPress) -> KeyPress.Result {
        guard let session = appState.importSession else { return .ignored }
        guard let digit = Int(String(press.characters)) else { return .ignored }
        let index = digit - 1
        guard index >= 0, index < session.tags.count else { return .ignored }
        let tag = session.tags[index]

        let targetIDs: Set<UUID>
        if let focused = focusedClipID {
            targetIDs = [focused]
        } else if !appState.selectedClipIDs.isEmpty {
            targetIDs = appState.selectedClipIDs
        } else if let hovered = hoveredClip, visibleClipIDs.contains(hovered.id) {
            targetIDs = [hovered.id]
        } else {
            return .ignored
        }

        let allHaveTag = targetIDs.allSatisfy { id in
            session.allClips.first { $0.id == id }?.tagIDs.contains(tag.id) == true
        }
        if allHaveTag {
            session.removeTag(tag.id, fromClipIDs: targetIDs)
        } else {
            session.assignTag(tag.id, toClipIDs: targetIDs)
        }
        return .handled
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
