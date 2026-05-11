//
//  ClipGridViewModel.swift
//  Framwise
//
//  Manages clip grid display and selection state
//

import Foundation
import Combine

@MainActor
class ClipGridViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .original
    @Published var viewMode: ViewMode = .all
    @Published var groupSimilar: Bool = false
    @Published var similarityGroupFilter: UUID? = nil
    private var selectionAnchorID: UUID?

    enum SortOrder {
        case original
        case duration
        case filename
        case similarity
    }

    enum ViewMode: String, CaseIterable {
        case all = "All"
        case selected = "Selected"

        var systemImage: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .selected: return "checkmark.square"
            }
        }
    }

    // MARK: - Cached Filter Results

    /// Cache key inputs
    private struct FilterInput: Equatable {
        struct ClipFilterState: Equatable {
            let id: UUID
            let wasteType: WasteType
            let wasteOverride: WasteType?
            let tagIDs: [UUID]
            let similarityGroupID: UUID?
        }

        let clipStates: [ClipFilterState]
        let selectedIDs: Set<UUID>
        let sourceURL: URL?
        let tagFilter: UUID?
        let hideWaste: Bool
        let searchText: String
        let sortOrder: SortOrder
        let viewMode: ViewMode
        let similarityGroupFilter: UUID?
        let groupSimilar: Bool
    }

    private var cachedInput: FilterInput?
    private var cachedFilteredClips: [VideoClip] = []
    private var cachedGroupedClips: [(sourceURL: URL, clips: [VideoClip])]? = nil

    /// Filter and sort clips based on current settings (cached)
    func filteredClips(from allClips: [VideoClip], selectedIDs: Set<UUID> = [], sourceURL: URL? = nil, tagFilter: UUID? = nil, hideWaste: Bool = false) -> [VideoClip] {
        let input = FilterInput(
            clipStates: allClips.map {
                FilterInput.ClipFilterState(
                    id: $0.id,
                    wasteType: $0.wasteType,
                    wasteOverride: $0.wasteOverride,
                    tagIDs: $0.tagIDs.sorted { $0.uuidString < $1.uuidString },
                    similarityGroupID: $0.similarityGroupID
                )
            },
            selectedIDs: selectedIDs,
            sourceURL: sourceURL,
            tagFilter: tagFilter,
            hideWaste: hideWaste,
            searchText: searchText,
            sortOrder: sortOrder,
            viewMode: viewMode,
            similarityGroupFilter: similarityGroupFilter,
            groupSimilar: groupSimilar
        )

        if cachedInput == input {
            return cachedFilteredClips
        }

        let result = computeFilteredClips(from: allClips, selectedIDs: selectedIDs, sourceURL: sourceURL, tagFilter: tagFilter, hideWaste: hideWaste)
        cachedInput = input
        cachedFilteredClips = result
        // Invalidate grouped cache when filtered changes
        cachedGroupedClips = nil
        return result
    }

    /// Group clips by source file (cached, depends on filteredClips)
    func groupedClips(from allClips: [VideoClip], selectedIDs: Set<UUID> = [], sourceURL: URL? = nil, tagFilter: UUID? = nil, hideWaste: Bool = false) -> [(sourceURL: URL, clips: [VideoClip])] {
        // groupedClips depends on filteredClips, so first ensure filtered cache is warm
        let _ = filteredClips(from: allClips, selectedIDs: selectedIDs, sourceURL: sourceURL, tagFilter: tagFilter, hideWaste: hideWaste)

        if let cached = cachedGroupedClips {
            return cached
        }

        let result = computeGroupedClips(from: cachedFilteredClips, sourceURL: sourceURL)
        cachedGroupedClips = result
        return result
    }

    // MARK: - Actual Computation (private)

    /// Shared content filters (waste, source, tag, similarity group, search).
    /// Excludes viewMode and sorting — callers layer those on as needed.
    private func applyContentFilters(_ clips: [VideoClip], sourceURL: URL?, tagFilter: UUID?, hideWaste: Bool) -> [VideoClip] {
        var result = clips
        if hideWaste { result = result.filter { $0.effectiveWasteType == .none } }
        if let url = sourceURL { result = result.filter { $0.sourceFileURL == url } }
        if let tagFilter = tagFilter { result = result.filter { $0.tagIDs.contains(tagFilter) } }
        if let groupFilter = similarityGroupFilter { result = result.filter { $0.similarityGroupID == groupFilter } }
        if !searchText.isEmpty { result = result.filter { $0.sourceFileName.localizedCaseInsensitiveContains(searchText) } }
        return result
    }

    private func computeFilteredClips(from allClips: [VideoClip], selectedIDs: Set<UUID>, sourceURL: URL?, tagFilter: UUID?, hideWaste: Bool) -> [VideoClip] {
        var result = applyContentFilters(allClips, sourceURL: sourceURL, tagFilter: tagFilter, hideWaste: hideWaste)

        if viewMode == .selected {
            result = result.filter { selectedIDs.contains($0.id) }
        }

        switch sortOrder {
        case .original:
            break
        case .duration:
            result.sort { $0.duration > $1.duration }
        case .filename:
            result.sort { $0.sourceFileName < $1.sourceFileName }
        case .similarity:
            result = sortBySimilarityGroup(result)
        }

        if groupSimilar && sortOrder != .similarity {
            result = sortBySimilarityGroup(result)
        }

        return result
    }

    /// Reorder clips so that similarity group members are adjacent,
    /// preserving relative order otherwise. Ungrouped clips come last.
    private func sortBySimilarityGroup(_ clips: [VideoClip]) -> [VideoClip] {
        var grouped: [UUID: [VideoClip]] = [:]
        var groupOrder: [UUID] = []
        var ungrouped: [VideoClip] = []

        for clip in clips {
            if let gid = clip.similarityGroupID {
                if grouped[gid] == nil {
                    groupOrder.append(gid)
                    grouped[gid] = []
                }
                grouped[gid]?.append(clip)
            } else {
                ungrouped.append(clip)
            }
        }

        var result: [VideoClip] = []
        for gid in groupOrder {
            result.append(contentsOf: grouped[gid] ?? [])
        }
        result.append(contentsOf: ungrouped)
        return result
    }

    private func computeGroupedClips(from filtered: [VideoClip], sourceURL: URL?) -> [(sourceURL: URL, clips: [VideoClip])] {
        // If filtering by a specific source URL, don't group (only one group)
        if let sourceURL = sourceURL {
            return [(sourceURL: sourceURL, clips: filtered)]
        }

        // 按 sourceURL 分组
        var groups: [URL: [VideoClip]] = [:]
        var groupOrder: [URL] = []

        for clip in filtered {
            if groups[clip.sourceFileURL] == nil {
                groups[clip.sourceFileURL] = []
                groupOrder.append(clip.sourceFileURL)
            }
            groups[clip.sourceFileURL]?.append(clip)
        }

        // 保持原始顺序
        return groupOrder.map { url in
            (sourceURL: url, clips: groups[url] ?? [])
        }
    }

    /// Toggle selection for a clip
    func toggleSelection(_ clipId: UUID, in appState: AppState) {
        if appState.selectedClipIDs.contains(clipId) {
            appState.selectedClipIDs.remove(clipId)
        } else {
            appState.selectedClipIDs.insert(clipId)
        }
        selectionAnchorID = clipId
    }

    /// Handle direct clip interaction, including shift-range selection.
    func handleSelection(_ clipId: UUID, visibleClipIDs: [UUID], in appState: AppState, extendRangeSelection: Bool) {
        guard extendRangeSelection else {
            toggleSelection(clipId, in: appState)
            return
        }

        guard
            let anchorID = selectionAnchorID,
            let anchorIndex = visibleClipIDs.firstIndex(of: anchorID),
            let targetIndex = visibleClipIDs.firstIndex(of: clipId)
        else {
            toggleSelection(clipId, in: appState)
            return
        }

        let bounds = anchorIndex <= targetIndex ? anchorIndex...targetIndex : targetIndex...anchorIndex
        appState.selectedClipIDs.formUnion(visibleClipIDs[bounds])
        selectionAnchorID = clipId
    }

    /// Select all clips in current view
    func selectAll(_ clips: [VideoClip], in appState: AppState) {
        appState.selectedClipIDs = Set(clips.map { $0.id })
        selectionAnchorID = clips.last?.id
    }

    /// Deselect all clips
    func deselectAll(in appState: AppState) {
        appState.selectedClipIDs.removeAll()
        selectionAnchorID = nil
    }

    /// Returns clips filtered by all active criteria EXCEPT viewMode.
    /// Used by Invert Selection so it operates against the correct pool
    /// even when viewMode == .selected (which would otherwise self-cancel).
    func clipsForInversion(from allClips: [VideoClip], sourceURL: URL?, tagFilter: UUID?, hideWaste: Bool) -> [VideoClip] {
        applyContentFilters(allClips, sourceURL: sourceURL, tagFilter: tagFilter, hideWaste: hideWaste)
    }

    /// Invert selection within the given clips, preserving selections outside the view
    func invertSelection(_ clips: [VideoClip], in appState: AppState) {
        let viewIDs = Set(clips.map { $0.id })
        let currentlySelectedInView = appState.selectedClipIDs.intersection(viewIDs)
        let invertedInView = viewIDs.subtracting(currentlySelectedInView)
        // Remove all view clips from selection, then add back the inverted ones
        appState.selectedClipIDs.subtract(viewIDs)
        appState.selectedClipIDs.formUnion(invertedInView)
        selectionAnchorID = clips.last?.id
    }

    /// Applies the user's manual clip order only when no explicit ordering mode
    /// is active. Group-similar and non-original sort modes should be visible.
    func displayOrderedClips(_ filteredClips: [VideoClip], userClipOrder: [UUID]?) -> [VideoClip] {
        guard let userClipOrder,
              !groupSimilar,
              sortOrder == .original else {
            return filteredClips
        }

        let filteredSet = Set(filteredClips.map(\.id))
        let clipMap = Dictionary(uniqueKeysWithValues: filteredClips.map { ($0.id, $0) })
        return userClipOrder.compactMap { id in
            filteredSet.contains(id) ? clipMap[id] : nil
        }
    }

    func resetTransientUIState() {
        searchText = ""
        sortOrder = .original
        viewMode = .all
        groupSimilar = false
        similarityGroupFilter = nil
        selectionAnchorID = nil
    }
}
