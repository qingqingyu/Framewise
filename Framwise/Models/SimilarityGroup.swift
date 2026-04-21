//
//  SimilarityGroup.swift
//  Framwise
//
//  A group of visually similar clips (repeated takes of the same shot)
//

import Foundation

struct SimilarityGroup: Identifiable, Codable {
    let id: UUID
    var clipIDs: [UUID]
    var representativeClipID: UUID

    var count: Int { clipIDs.count }

    init(id: UUID = UUID(), clipIDs: [UUID], representativeClipID: UUID) {
        self.id = id
        self.clipIDs = clipIDs
        self.representativeClipID = representativeClipID
    }
}
