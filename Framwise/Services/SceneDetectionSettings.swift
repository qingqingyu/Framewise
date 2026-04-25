//
//  SceneDetectionSettings.swift
//  Framwise
//
//  Maps user-facing scene sensitivity to the detector threshold and
//  migrates stored settings when the semantic meaning changes.
//

import Foundation

enum SceneDetectionSettings {

    // MARK: - Tile Count Bounds (single source of truth)

    static let minTileCount = 12
    static let maxTileCount = 120
    static let defaultTileCount = 36
    static let tileCountStep = 12

    // MARK: - Legacy Migration
    // Retained for one-time upgrade from versions where users stored a manual
    // sensitivity value in UserDefaults. Safe to remove once the installed base
    // has migrated (post-v5 release cycle).

    static let sensitivityKey = "sceneDetectionSensitivity"
    static let didMigrateSensitivityKey = "didMigrateSceneDetectionSensitivityV2"
    static let supportedRange: ClosedRange<Double> = 0.1...0.9
    static let defaultUISensitivity = 0.7

    static func threshold(forUISensitivity value: Double) -> Double {
        let clampedValue = clamped(value)
        return clamped(1.0 - clampedValue)
    }

    static func migrateStoredSensitivityIfNeeded(userDefaults: UserDefaults = .standard) {
        guard !userDefaults.bool(forKey: didMigrateSensitivityKey) else { return }
        defer {
            userDefaults.set(true, forKey: didMigrateSensitivityKey)
        }

        guard let storedValue = userDefaults.object(forKey: sensitivityKey) as? NSNumber else { return }
        let migratedValue = clamped(1.0 - storedValue.doubleValue)
        userDefaults.set(migratedValue, forKey: sensitivityKey)
    }

    // MARK: - Auto Sensitivity

    /// Floor / ceiling for the auto-derived sensitivity.
    /// Narrower than `supportedRange` — even at minimum tiles we want meaningful detection.
    private static let autoSensitivityFloor = 0.3
    private static let autoSensitivityCeiling = 0.9

    /// Derive scene detection sensitivity from the user's target tile count.
    /// More tiles → higher sensitivity → more scene cuts detected.
    /// Linear mapping: minTileCount → 0.3, maxTileCount → 0.9.
    static func autoSensitivity(forTargetCount count: Int) -> Double {
        let span = maxTileCount - minTileCount
        guard span > 0 else { return autoSensitivityFloor }
        let ratio = Double(count - minTileCount) / Double(span)
        let t = min(max(ratio, 0.0), 1.0)
        return autoSensitivityFloor + t * (autoSensitivityCeiling - autoSensitivityFloor)
    }

    static func clamped(_ value: Double) -> Double {
        min(max(value, supportedRange.lowerBound), supportedRange.upperBound)
    }
}
