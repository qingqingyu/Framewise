//
//  AppLogger.swift
//  Framwise
//
//  Structured logging helpers shared across app layers.
//

import Foundation
import os
import CryptoKit

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Framwise"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    static let fileResolution = Logger(subsystem: subsystem, category: "FileResolution")
    static let importFlow = Logger(subsystem: subsystem, category: "Import")
    static let export = Logger(subsystem: subsystem, category: "Export")
    static let preview = Logger(subsystem: subsystem, category: "Preview")
    static let thumbnails = Logger(subsystem: subsystem, category: "Thumbnails")

    static func info(_ logger: Logger, _ message: String, context: [String: Any] = [:]) {
        logger.info("\(message, privacy: .public) | context=\(contextDescription(context), privacy: .public)")
    }

    static func warning(_ logger: Logger, _ message: String, context: [String: Any] = [:]) {
        logger.warning("\(message, privacy: .public) | context=\(contextDescription(context), privacy: .public)")
    }

    static func error(_ logger: Logger, _ message: String, error: Error, context: [String: Any] = [:]) {
        logger.error("\(message, privacy: .public) | context=\(contextDescription(context), privacy: .public) | error=\(String(reflecting: error), privacy: .public)")
    }

    static func durationMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    static func fileReference(_ url: URL) -> String {
        "\(url.lastPathComponent)#\(shortHash(url.path))"
    }

    static func pathReference(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return "\(name)#\(shortHash(path))"
    }

    private static func contextDescription(_ context: [String: Any]) -> String {
        guard !context.isEmpty else { return "{}" }
        return context
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(String(describing: $0.value))" }
            .joined(separator: ", ")
    }

    private static func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
