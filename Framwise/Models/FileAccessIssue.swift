//
//  FileAccessIssue.swift
//  Framwise
//
//  Represents a file access problem discovered during import or session restore.
//

import Foundation

struct FileAccessIssue: Identifiable {
    enum Kind: String {
        case missing
        case unreadable
        case enumerationFailed
        case metadataReadFailed
        case changed
        case videoLimitReached
    }

    let id = UUID()
    let url: URL
    let kind: Kind

    init(url: URL, kind: Kind) {
        self.url = url
        self.kind = kind
    }

    var title: String {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Selected source" : name
    }

    var message: String {
        switch kind {
        case .missing:
            return "Source is missing or unavailable. Reconnect the volume or choose it again."
        case .unreadable:
            return "Source cannot be read. Check file permissions or choose it again."
        case .enumerationFailed:
            return "Folder contents could not be scanned. Check permissions or reconnect the volume."
        case .metadataReadFailed:
            return "Source metadata could not be read. Check permissions or choose it again."
        case .changed:
            return "Source changed since the last session. Import it again to refresh clips."
        case .videoLimitReached:
            return "Folder scan stopped after reaching the import limit. Split the source into smaller batches to import the rest."
        }
    }
}
