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
}
