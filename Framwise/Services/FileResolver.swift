//
//  FileResolver.swift
//  Framwise
//
//  Resolves mixed file/folder URLs into flat lists of video files

import Foundation

enum FileResolver {
    struct ResolveResult {
        var videoURLs: [URL]
        var unsupportedNames: [String]
        var accessIssues: [FileAccessIssue]
        var suppressedAccessIssueCount: Int
        var didReachVideoLimit: Bool

        var accessIssueCount: Int {
            accessIssues.count + suppressedAccessIssueCount
        }
    }

    /// Supported video file extensions (single source of truth)
    static let supportedVideoExtensions: Set<String> = ["mp4", "mov", "mxf", "avi", "mkv", "m4v"]

    /// Hard cap to prevent runaway enumeration on huge directory trees
    private static let maxVideoFiles = 5000
    private static let maxAccessIssues = 50

    /// Resolve a list of URLs (files and/or folders) into flat video file URLs.
    /// Folders are scanned recursively with symlink-cycle protection and a file count cap.
    static func resolveVideoURLsInBackground(from urls: [URL]) async -> ResolveResult {
        let task = Task.detached(priority: .userInitiated) {
            resolveVideoURLs(from: urls)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func resolveVideoURLs(from urls: [URL]) -> ResolveResult {
        let start = Date()
        let fm = FileManager.default
        var videoURLs: [URL] = []
        var unsupported: [String] = []
        var accessIssues: [FileAccessIssue] = []
        var suppressedAccessIssueCount = 0
        var visitedRealPaths: Set<String> = []
        var didReachVideoLimit = false

        @discardableResult
        func recordAccessIssue(_ issue: FileAccessIssue) -> Bool {
            if accessIssues.count < Self.maxAccessIssues {
                accessIssues.append(issue)
                return true
            } else {
                suppressedAccessIssueCount += 1
                return false
            }
        }

        func recordVideoLimitReached(at url: URL) {
            guard !didReachVideoLimit else { return }
            didReachVideoLimit = true
            let issue = FileAccessIssue(url: url, kind: .videoLimitReached)
            if accessIssues.count < Self.maxAccessIssues {
                accessIssues.append(issue)
            } else if !accessIssues.isEmpty {
                accessIssues[accessIssues.count - 1] = issue
                suppressedAccessIssueCount += 1
            } else {
                _ = recordAccessIssue(issue)
            }
        }

        for url in urls {
            if Task.isCancelled {
                AppLogger.warning(AppLogger.fileResolution, "Video resolution cancelled", context: [
                    "inputCount": urls.count,
                    "videoCount": videoURLs.count,
                    "accessIssueCount": accessIssues.count + suppressedAccessIssueCount
                ])
                break
            }

            if videoURLs.count >= maxVideoFiles {
                recordVideoLimitReached(at: url)
                AppLogger.warning(AppLogger.fileResolution, "Video resolution stopped at cap", context: [
                    "maxVideoFiles": maxVideoFiles,
                    "inputCount": urls.count
                ])
                break
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                if recordAccessIssue(FileAccessIssue(url: url, kind: .missing)) {
                    AppLogger.warning(AppLogger.fileResolution, "Dropped URL does not exist", context: [
                        "url": AppLogger.fileReference(url)
                    ])
                }
                continue
            }

            guard fm.isReadableFile(atPath: url.path) else {
                if recordAccessIssue(FileAccessIssue(url: url, kind: .unreadable)) {
                    AppLogger.warning(AppLogger.fileResolution, "Dropped URL is not readable", context: [
                        "url": AppLogger.fileReference(url)
                    ])
                }
                continue
            }

            if isDir.boolValue {
                let realDir: String
                do {
                    realDir = try url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath ?? url.path
                } catch {
                    if recordAccessIssue(FileAccessIssue(url: url, kind: .metadataReadFailed)) {
                        AppLogger.error(AppLogger.fileResolution, "Failed to read canonical path for directory", error: error, context: [
                            "url": AppLogger.fileReference(url)
                        ])
                    }
                    continue
                }
                guard visitedRealPaths.insert(realDir).inserted else { continue }

                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .canonicalPathKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { failedURL, error in
                        guard !Task.isCancelled else { return false }
                        if recordAccessIssue(FileAccessIssue(url: failedURL, kind: .enumerationFailed)) {
                            AppLogger.error(AppLogger.fileResolution, "Failed to enumerate directory item", error: error, context: [
                                "url": AppLogger.fileReference(failedURL)
                            ])
                        }
                        return true
                    }
                ) else {
                    if recordAccessIssue(FileAccessIssue(url: url, kind: .enumerationFailed)) {
                        AppLogger.warning(AppLogger.fileResolution, "Could not enumerate dropped directory", context: [
                            "url": AppLogger.fileReference(url)
                        ])
                    }
                    continue
                }

                for case let fileURL as URL in enumerator {
                    if Task.isCancelled {
                        AppLogger.warning(AppLogger.fileResolution, "Directory video resolution cancelled", context: [
                            "url": AppLogger.fileReference(url),
                            "videoCount": videoURLs.count,
                            "accessIssueCount": accessIssues.count + suppressedAccessIssueCount
                        ])
                        break
                    }

                    if videoURLs.count >= maxVideoFiles {
                        recordVideoLimitReached(at: url)
                        AppLogger.warning(AppLogger.fileResolution, "Directory video resolution stopped at cap", context: [
                            "url": AppLogger.fileReference(url),
                            "maxVideoFiles": maxVideoFiles,
                            "inputCount": urls.count
                        ])
                        break
                    }

                    do {
                        let vals = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .canonicalPathKey])
                        if vals.isSymbolicLink == true {
                            let real = vals.canonicalPath ?? fileURL.path
                            guard visitedRealPaths.insert(real).inserted else {
                                enumerator.skipDescendants()
                                continue
                            }
                        } else if vals.isRegularFile != true {
                            continue
                        }
                    } catch {
                        if recordAccessIssue(FileAccessIssue(url: fileURL, kind: .metadataReadFailed)) {
                            AppLogger.error(AppLogger.fileResolution, "Failed to read file resource values", error: error, context: [
                                "url": AppLogger.fileReference(fileURL)
                            ])
                        }
                        continue
                    }

                    if supportedVideoExtensions.contains(fileURL.pathExtension.lowercased()) {
                        var isVideoDirectory: ObjCBool = false
                        guard fm.fileExists(atPath: fileURL.path, isDirectory: &isVideoDirectory),
                              !isVideoDirectory.boolValue else {
                            continue
                        }
                        guard fm.isReadableFile(atPath: fileURL.path) else {
                            if recordAccessIssue(FileAccessIssue(url: fileURL, kind: .unreadable)) {
                                AppLogger.warning(AppLogger.fileResolution, "Resolved video is not readable", context: [
                                    "url": AppLogger.fileReference(fileURL)
                                ])
                            }
                            continue
                        }
                        videoURLs.append(fileURL)
                    }
                }
            } else if supportedVideoExtensions.contains(url.pathExtension.lowercased()) {
                videoURLs.append(url)
            } else {
                unsupported.append(url.lastPathComponent)
            }
        }
        if suppressedAccessIssueCount > 0 {
            AppLogger.warning(AppLogger.fileResolution, "Suppressed additional file access issues", context: [
                "suppressedAccessIssueCount": suppressedAccessIssueCount,
                "capturedAccessIssueCount": accessIssues.count
            ])
        }
        AppLogger.info(AppLogger.fileResolution, "Resolved dropped URLs", context: [
            "inputCount": urls.count,
            "videoCount": videoURLs.count,
            "unsupportedCount": unsupported.count,
            "accessIssueCount": accessIssues.count + suppressedAccessIssueCount,
            "suppressedAccessIssueCount": suppressedAccessIssueCount,
            "didReachVideoLimit": didReachVideoLimit,
            "durationMs": AppLogger.durationMilliseconds(since: start)
        ])
        return ResolveResult(
            videoURLs: videoURLs,
            unsupportedNames: unsupported,
            accessIssues: accessIssues,
            suppressedAccessIssueCount: suppressedAccessIssueCount,
            didReachVideoLimit: didReachVideoLimit
        )
    }
}
