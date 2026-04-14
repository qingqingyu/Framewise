//
//  ImportSession.swift
//  Framwise
//
//  Represents an import session containing all clips from imported videos
//

import Foundation
import AVFoundation

@MainActor
class ImportSession: ObservableObject {
    let id = UUID()
    let createdDate = Date()

    @Published var sourceFiles: [URL] = []
    @Published var allClips: [VideoClip] = []
    @Published var isAnalyzed = false
    @Published var userClipOrder: [UUID]? = nil
    @Published var tags: [ClipTag] = []
    @Published var activeTagFilter: UUID? = nil  // nil = show all

    var totalDuration: Double {
        allClips.reduce(0) { $0 + $1.duration }
    }

    var clipCount: Int {
        allClips.count
    }

    func addClips(_ clips: [VideoClip]) {
        allClips.append(contentsOf: clips)
        // If user has a custom order, append new clips at the end
        if userClipOrder != nil {
            userClipOrder!.append(contentsOf: clips.map { $0.id })
        }
    }

    func addClip(_ clip: VideoClip) {
        allClips.append(clip)
        if userClipOrder != nil {
            userClipOrder!.append(clip.id)
        }
    }

    func addSourceFile(_ url: URL) {
        if !sourceFiles.contains(url) {
            sourceFiles.append(url)
        }
    }

    func clear() {
        sourceFiles.removeAll()
        allClips.removeAll()
        isAnalyzed = false
        userClipOrder = nil
        tags.removeAll()
        activeTagFilter = nil
    }

    func moveClip(_ draggedID: UUID, toTarget targetID: UUID) {
        var order = userClipOrder ?? allClips.map { $0.id }
        guard let sourceIndex = order.firstIndex(of: draggedID),
              let targetIndex = order.firstIndex(of: targetID),
              sourceIndex != targetIndex else { return }

        order.remove(at: sourceIndex)
        let insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        order.insert(draggedID, at: insertIndex)
        userClipOrder = order
    }

    func resetClipOrder() {
        userClipOrder = nil
    }

    // MARK: - Tag CRUD

    func addTag(_ tag: ClipTag) {
        // Skip if a tag with the same name already exists
        let existingNames = Set(tags.map { $0.name })
        guard !existingNames.contains(tag.name) else { return }
        tags.append(tag)
    }

    func removeTag(_ tagID: UUID) {
        tags.removeAll { $0.id == tagID }
        // Remove from all clips
        for i in allClips.indices {
            allClips[i].tagIDs.remove(tagID)
        }
        if activeTagFilter == tagID {
            activeTagFilter = nil
        }
    }

    func renameTag(_ tagID: UUID, to name: String) {
        if let index = tags.firstIndex(where: { $0.id == tagID }) {
            tags[index].name = name
        }
    }

    // MARK: - Clip Tag Assignment

    func assignTag(_ tagID: UUID, to clipID: UUID) {
        if let index = allClips.firstIndex(where: { $0.id == clipID }) {
            allClips[index].tagIDs.insert(tagID)
        }
    }

    func assignTag(_ tagID: UUID, toClipIDs clipIDs: Set<UUID>) {
        let targetSet = clipIDs
        for i in allClips.indices where targetSet.contains(allClips[i].id) {
            allClips[i].tagIDs.insert(tagID)
        }
    }

    func removeTag(_ tagID: UUID, from clipID: UUID) {
        if let index = allClips.firstIndex(where: { $0.id == clipID }) {
            allClips[index].tagIDs.remove(tagID)
        }
    }

    func removeTag(_ tagID: UUID, fromClipIDs clipIDs: Set<UUID>) {
        let targetSet = clipIDs
        for i in allClips.indices where targetSet.contains(allClips[i].id) {
            allClips[i].tagIDs.remove(tagID)
        }
    }

    func clipsWithTag(_ tagID: UUID) -> [VideoClip] {
        allClips.filter { $0.tagIDs.contains(tagID) }
    }

    func clipCount(for tagID: UUID) -> Int {
        clipsWithTag(tagID).count
    }

    // MARK: - Wedding Preset

    static func weddingPresetTags() -> [ClipTag] {
        [
            ClipTag(name: "新娘准备", color: .pink),
            ClipTag(name: "新郎准备", color: .blue),
            ClipTag(name: "仪式", color: .purple),
            ClipTag(name: "晚宴", color: .orange),
            ClipTag(name: "第一支舞", color: .green),
            ClipTag(name: "花絮", color: .yellow),
        ]
    }

    func loadWeddingPreset() {
        let preset = Self.weddingPresetTags()
        let existingNames = Set(tags.map { $0.name })
        for tag in preset where !existingNames.contains(tag.name) {
            tags.append(tag)
        }
    }

    // MARK: - Restore from persisted data

    func restore(from data: SessionStore.SessionData) {
        sourceFiles = data.sourceFiles
        allClips = data.allClips
        isAnalyzed = data.isAnalyzed
        userClipOrder = data.userClipOrder
        tags = data.tags

        // Validate activeTagFilter references an existing tag
        if let filter = data.activeTagFilter {
            let tagIDs = Set(tags.map { $0.id })
            activeTagFilter = tagIDs.contains(filter) ? filter : nil
        } else {
            activeTagFilter = nil
        }

        // Remove source files that no longer exist on disk
        let fm = FileManager.default
        let validSourceURLs = Set(sourceFiles.filter { url in
            fm.fileExists(atPath: url.path)
        })
        sourceFiles.removeAll { !validSourceURLs.contains($0) }

        // Remove clips whose source file no longer exists
        if sourceFiles.count < data.sourceFiles.count {
            allClips.removeAll { !validSourceURLs.contains($0.sourceFileURL) }

            // Clean up userClipOrder to remove stale IDs
            if var order = userClipOrder {
                let remainingIDs = Set(allClips.map { $0.id })
                order.removeAll { !remainingIDs.contains($0) }
                userClipOrder = order.isEmpty ? nil : order
            }
        }
    }
}
