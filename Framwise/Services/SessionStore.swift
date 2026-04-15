//
//  SessionStore.swift
//  Framwise
//
//  Persists import session data to disk for crash recovery and app restart
//

import Foundation

@MainActor
class SessionStore {
    static let currentVersion = 1

    struct SessionData: Codable {
        let version: Int
        let id: UUID
        let createdDate: Date
        let sourceFiles: [URL]
        let allClips: [VideoClip]
        let isAnalyzed: Bool
        let userClipOrder: [UUID]?
        let tags: [ClipTag]
        let activeTagFilter: UUID?
        let selectedClipIDs: Set<UUID>

        enum CodingKeys: String, CodingKey {
            case version, id, createdDate, sourceFiles, allClips
            case isAnalyzed, userClipOrder, tags, activeTagFilter, selectedClipIDs
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
            id = try c.decode(UUID.self, forKey: .id)
            createdDate = try c.decode(Date.self, forKey: .createdDate)
            sourceFiles = try c.decode([URL].self, forKey: .sourceFiles)
            allClips = try c.decode([VideoClip].self, forKey: .allClips)
            isAnalyzed = try c.decode(Bool.self, forKey: .isAnalyzed)
            userClipOrder = try c.decodeIfPresent([UUID].self, forKey: .userClipOrder)
            tags = try c.decodeIfPresent([ClipTag].self, forKey: .tags) ?? []
            activeTagFilter = try c.decodeIfPresent(UUID.self, forKey: .activeTagFilter)
            selectedClipIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .selectedClipIDs) ?? []
        }

        init(version: Int, id: UUID, createdDate: Date, sourceFiles: [URL],
             allClips: [VideoClip], isAnalyzed: Bool, userClipOrder: [UUID]?,
             tags: [ClipTag], activeTagFilter: UUID?, selectedClipIDs: Set<UUID>) {
            self.version = version
            self.id = id
            self.createdDate = createdDate
            self.sourceFiles = sourceFiles
            self.allClips = allClips
            self.isAnalyzed = isAnalyzed
            self.userClipOrder = userClipOrder
            self.tags = tags
            self.activeTagFilter = activeTagFilter
            self.selectedClipIDs = selectedClipIDs
        }
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
            version: Self.currentVersion,
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
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: fileURL, options: .atomic)
    }

    func load() throws -> SessionData? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let jsonData = try Data(contentsOf: fileURL)

        // Try iso8601 first (current format), fall back to double (legacy format)
        let decoder = JSONDecoder()
        var data: SessionData
        if let decoded = try? decodeWithISO8601(jsonData) {
            data = decoded
        } else {
            data = try decodeWithDoubleDate(jsonData)
        }

        // Forward-migrate older versions
        if data.version < Self.currentVersion {
            data = migrate(data)
        }
        return data
    }

    private func decodeWithISO8601(_ data: Data) throws -> SessionData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionData.self, from: data)
    }

    private func decodeWithDoubleDate(_ data: Data) throws -> SessionData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(SessionData.self, from: data)
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Migration

    private func migrate(_ data: SessionData) -> SessionData {
        // Add future migrations here, e.g.:
        // if data.version < 2 { data = migrateV1toV2(data) }
        return SessionData(
            version: Self.currentVersion,
            id: data.id,
            createdDate: data.createdDate,
            sourceFiles: data.sourceFiles,
            allClips: data.allClips,
            isAnalyzed: data.isAnalyzed,
            userClipOrder: data.userClipOrder,
            tags: data.tags,
            activeTagFilter: data.activeTagFilter,
            selectedClipIDs: data.selectedClipIDs
        )
    }
}
