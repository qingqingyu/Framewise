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
    @Published var similarityGroups: [SimilarityGroup] = []

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

    @discardableResult
    func addSourceFile(_ url: URL) -> Bool {
        guard !sourceFiles.contains(url) else { return false }
        sourceFiles.append(url)
        return true
    }

    func removeSourceFile(_ url: URL) {
        sourceFiles.removeAll { $0 == url }
        let removedClipIDs = Set(allClips.filter { $0.sourceFileURL == url }.map(\.id))
        allClips.removeAll { $0.sourceFileURL == url }
        if var order = userClipOrder {
            order.removeAll { removedClipIDs.contains($0) }
            userClipOrder = order.isEmpty ? nil : order
        }
        // Clean up similarity groups referencing removed clips
        for i in similarityGroups.indices.reversed() {
            similarityGroups[i].clipIDs.removeAll { removedClipIDs.contains($0) }
            if similarityGroups[i].clipIDs.count < 2 {
                let orphanedGroupID = similarityGroups[i].id
                similarityGroups.remove(at: i)
                for j in allClips.indices where allClips[j].similarityGroupID == orphanedGroupID {
                    allClips[j].similarityGroupID = nil
                }
            }
        }
    }

    func clear() {
        sourceFiles.removeAll()
        allClips.removeAll()
        isAnalyzed = false
        userClipOrder = nil
        tags.removeAll()
        activeTagFilter = nil
        similarityGroups.removeAll()
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

    @discardableResult
    func addTag(_ tag: ClipTag) -> Bool {
        let trimmedName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let existingNames = Set(tags.map { normalizeTagName($0.name) })
        guard !existingNames.contains(normalizeTagName(trimmedName)) else { return false }

        tags.append(ClipTag(id: tag.id, name: trimmedName, color: tag.color))
        return true
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

    @discardableResult
    func renameTag(_ tagID: UUID, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        let existingNames = Set(tags.filter { $0.id != tagID }.map { normalizeTagName($0.name) })
        guard !existingNames.contains(normalizeTagName(trimmedName)) else { return false }

        guard let index = tags.firstIndex(where: { $0.id == tagID }) else { return false }
        tags[index].name = trimmedName
        return true
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
        let existingNames = Set(tags.map { normalizeTagName($0.name) })
        for tag in preset where !existingNames.contains(normalizeTagName(tag.name)) {
            tags.append(tag)
        }
    }

    private func normalizeTagName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Restore from persisted data

    func restore(from data: SessionStore.SessionData) {
        sourceFiles = data.sourceFiles
        allClips = data.allClips
        isAnalyzed = data.isAnalyzed
        userClipOrder = data.userClipOrder
        tags = data.tags
        similarityGroups = data.similarityGroups

        // Validate activeTagFilter references an existing tag
        if let filter = data.activeTagFilter {
            let tagIDs = Set(tags.map { $0.id })
            activeTagFilter = tagIDs.contains(filter) ? filter : nil
        } else {
            activeTagFilter = nil
        }

        let fm = FileManager.default
        var removedAny = false

        // Build set of source files that still exist AND haven't been replaced
        let validSourceURLs: Set<URL> = Set(sourceFiles.filter { url in
            guard fm.fileExists(atPath: url.path) else { return false }
            // Check if file content changed since last save
            if let savedMeta = data.sourceFileMetadata[url] {
                return Self.isFileUnchanged(url: url, savedMeta: savedMeta, fm: fm)
            }
            // No metadata saved (legacy session) — accept as-is
            return true
        })

        if validSourceURLs.count < sourceFiles.count {
            sourceFiles.removeAll { !validSourceURLs.contains($0) }
            allClips.removeAll { !validSourceURLs.contains($0.sourceFileURL) }
            removedAny = true
        }

        // Clean up userClipOrder to remove stale IDs
        if removedAny {
            if var order = userClipOrder {
                let remainingIDs = Set(allClips.map { $0.id })
                order.removeAll { !remainingIDs.contains($0) }
                userClipOrder = order.isEmpty ? nil : order
            }
        }
    }

    /// Compare file mtime and size against saved metadata
    private static func isFileUnchanged(url: URL, savedMeta: SessionStore.FileMetadata, fm: FileManager) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int64 else {
            return false
        }
        // Allow 2-second mtime tolerance (filesystem granularity)
        return abs(mtime.timeIntervalSince1970 - savedMeta.modificationDate) < 2.0
            && size == savedMeta.fileSize
    }
}
