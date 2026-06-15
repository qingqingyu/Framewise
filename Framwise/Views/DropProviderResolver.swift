//
//  DropProviderResolver.swift
//  Framwise
//
//  Shared drag-provider URL resolution for import surfaces.
//

import Foundation

private enum DropProviderError: LocalizedError {
    case missingFileURL

    var errorDescription: String? {
        switch self {
        case .missingFileURL:
            return "Dropped item did not provide a file URL."
        }
    }
}

struct DropProviderResolution {
    let urls: [URL]
    let errors: [Error]

    var warnings: [ImportWarning] {
        errors.map(ImportWarning.droppedItem)
    }

    var allProvidersFailedError: ImportError? {
        urls.isEmpty && !errors.isEmpty ? .droppedItemsUnreadable(errors.count) : nil
    }
}

enum DropProviderResolver {
    static func resolveURLs(from providers: [NSItemProvider], surface: String) async -> DropProviderResolution {
        await resolveURLs(surface: surface, providerCount: providers.count) { providerIndex in
            await withCheckedContinuation { continuation in
                _ = providers[providerIndex].loadObject(ofClass: URL.self) { url, error in
                    if let error {
                        continuation.resume(returning: .failure(error))
                    } else {
                        continuation.resume(returning: .success(url))
                    }
                }
            }
        }
    }

    #if DEBUG
    static func resolveURLsForTesting(
        surface: String,
        providerCount: Int,
        loadURL: (Int) async -> Result<URL?, Error>
    ) async -> DropProviderResolution {
        await resolveURLs(surface: surface, providerCount: providerCount, loadURL: loadURL)
    }
    #endif

    private static func resolveURLs(
        surface: String,
        providerCount: Int,
        loadURL: (Int) async -> Result<URL?, Error>
    ) async -> DropProviderResolution {
        let start = Date()
        var droppedURLs: [URL] = []
        var providerErrors: [Error] = []

        for providerIndex in 0..<providerCount {
            let result = await loadURL(providerIndex)

            switch result {
            case .success(let url):
                if let url {
                    droppedURLs.append(url)
                } else {
                    let error = DropProviderError.missingFileURL
                    providerErrors.append(error)
                    AppLogger.error(AppLogger.fileResolution, "Drop provider returned no file URL", error: error, context: [
                        "surface": surface,
                        "providerIndex": providerIndex,
                        "providerCount": providerCount
                    ])
                }
            case .failure(let error):
                providerErrors.append(error)
                AppLogger.error(AppLogger.fileResolution, "Drop provider failed to load URL", error: error, context: [
                    "surface": surface,
                    "providerIndex": providerIndex,
                    "providerCount": providerCount
                ])
            }
        }

        if droppedURLs.isEmpty, let firstError = providerErrors.first {
            AppLogger.error(AppLogger.fileResolution, "All dropped providers failed to load URLs", error: firstError, context: [
                "surface": surface,
                "providerErrorCount": providerErrors.count
            ])
        }

        AppLogger.info(AppLogger.fileResolution, "Resolved drop providers", context: [
            "surface": surface,
            "providerCount": providerCount,
            "urlCount": droppedURLs.count,
            "providerErrorCount": providerErrors.count,
            "durationMs": AppLogger.durationMilliseconds(since: start)
        ])

        return DropProviderResolution(urls: droppedURLs, errors: providerErrors)
    }
}
