//
//  ImportSession.swift
//  Framwise
//
//  Represents an import session containing all clips from imported videos
//

import Foundation
import AVFoundation

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
    }

    func addClip(_ clip: VideoClip) {
        allClips.append(clip)
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

    func removeTag(_ tagID: UUID, from clipID: UUID) {
        if let index = allClips.firstIndex(where: { $0.id == clipID }) {
            allClips[index].tagIDs.remove(tagID)
        }
    }

    func clipsWithTag(_ tagID: UUID) -> [VideoClip] {
        allClips.filter { $0.tagIDs.contains(tagID) }
    }

    func clipCount(for tagID: UUID) -> Int {
        allClips.filter { $0.tagIDs.contains(tagID) }.count
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
}
