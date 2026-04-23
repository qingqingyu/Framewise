//
//  FileResolver.swift
//  Framwise
//
//  Resolves mixed file/folder URLs into flat lists of video files

import Foundation

enum FileResolver {
    /// Supported video file extensions (single source of truth)
    static let supportedVideoExtensions: Set<String> = ["mp4", "mov", "mxf", "avi", "mkv", "m4v"]

    /// Hard cap to prevent runaway enumeration on huge directory trees
    private static let maxVideoFiles = 5000

    /// Resolve a list of URLs (files and/or folders) into flat video file URLs.
    /// Folders are scanned recursively with symlink-cycle protection and a file count cap.
    static func resolveVideoURLs(from urls: [URL]) -> (videoURLs: [URL], unsupportedNames: [String]) {
        let fm = FileManager.default
        var videoURLs: [URL] = []
        var unsupported: [String] = []
        var visitedRealPaths: Set<String> = []

        for url in urls {
            if videoURLs.count >= maxVideoFiles { break }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let realDir = (try? url.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath ?? url.path
                guard visitedRealPaths.insert(realDir).inserted else { continue }

                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .canonicalPathKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    if videoURLs.count >= maxVideoFiles { break }

                    if let vals = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .canonicalPathKey]),
                       vals.isSymbolicLink == true {
                        let real = vals.canonicalPath ?? fileURL.path
                        guard visitedRealPaths.insert(real).inserted else {
                            enumerator.skipDescendants()
                            continue
                        }
                    }

                    if supportedVideoExtensions.contains(fileURL.pathExtension.lowercased()) {
                        videoURLs.append(fileURL)
                    }
                }
            } else if supportedVideoExtensions.contains(url.pathExtension.lowercased()) {
                videoURLs.append(url)
            } else {
                unsupported.append(url.lastPathComponent)
            }
        }
        return (videoURLs, unsupported)
    }
}
