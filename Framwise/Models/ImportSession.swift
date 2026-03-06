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

    var totalDuration: Double {
        allClips.reduce(0) { $0 + $1.duration }
    }

    var clipCount: Int {
        allClips.count
    }

    func addClips(_ clips: [VideoClip]) {
        allClips.append(contentsOf: clips)
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
    }
}
