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

    enum SortOrder {
        case original
        case duration
        case filename
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

    /// Filter and sort clips based on current settings
    func filteredClips(from allClips: [VideoClip], selectedIDs: Set<UUID> = [], sourceURL: URL? = nil) -> [VideoClip] {
        var result = allClips

        // Source file filter
        if let url = sourceURL {
            result = result.filter { $0.sourceFileURL == url }
        }

        // View mode filter
        if viewMode == .selected {
            result = result.filter { selectedIDs.contains($0.id) }
        }

        // Search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.sourceFileName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort
        switch sortOrder {
        case .original:
            break
        case .duration:
            result.sort { $0.duration > $1.duration }
        case .filename:
            result.sort { $0.sourceFileName < $1.sourceFileName }
        }

        return result
    }

    /// Group clips by source file
    func groupedClips(from allClips: [VideoClip], selectedIDs: Set<UUID> = [], sourceURL: URL? = nil) -> [(sourceURL: URL, clips: [VideoClip])] {
        let filtered = filteredClips(from: allClips, selectedIDs: selectedIDs, sourceURL: sourceURL)

        // If filtering by a specific source URL, don't group (only one group)
        if sourceURL != nil {
            return [(sourceURL: sourceURL!, clips: filtered)]
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
    }

    /// Select all clips in current view
    func selectAll(_ clips: [VideoClip], in appState: AppState) {
        appState.selectedClipIDs = Set(clips.map { $0.id })
    }

    /// Deselect all clips
    func deselectAll(in appState: AppState) {
        appState.selectedClipIDs.removeAll()
    }

    /// Invert selection
    func invertSelection(_ clips: [VideoClip], in appState: AppState) {
        let allIDs = Set(clips.map { $0.id })
        let currentSelection = appState.selectedClipIDs
        appState.selectedClipIDs = allIDs.subtracting(currentSelection)
    }
}
