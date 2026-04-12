//
//  SessionStore.swift
//  Framwise
//
//  Persists import session data to disk for crash recovery and app restart
//

import Foundation

class SessionStore {
    struct SessionData: Codable {
        let id: UUID
        let createdDate: Date
        let sourceFiles: [URL]
        let allClips: [VideoClip]
        let isAnalyzed: Bool
        let userClipOrder: [UUID]?
        let tags: [ClipTag]
        let activeTagFilter: UUID?
        let selectedClipIDs: Set<UUID>
    }

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Framwise", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("session.json")
    }

    func save(session: ImportSession, selectedClipIDs: Set<UUID>) throws {
        let data = SessionData(
            id: session.id,
            createdDate: session.createdDate,
            sourceFiles: session.sourceFiles,
            allClips: session.allClips,
            isAnalyzed: session.isAnalyzed,
            userClipOrder: session.userClipOrder,
            tags: session.tags,
            activeTagFilter: session.activeTagFilter,
            selectedClipIDs: selectedClipIDs
        )
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: fileURL, options: .atomic)
    }

    func load() throws -> SessionData? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let jsonData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(SessionData.self, from: jsonData)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
