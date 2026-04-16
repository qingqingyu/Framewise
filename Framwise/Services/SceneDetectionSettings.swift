//
//  SceneDetectionSettings.swift
//  Framwise
//
//  Maps user-facing scene sensitivity to the detector threshold and
//  migrates stored settings when the semantic meaning changes.
//

import Foundation

enum SceneDetectionSettings {
    static let sensitivityKey = "sceneDetectionSensitivity"
    static let didMigrateSensitivityKey = "didMigrateSceneDetectionSensitivityV2"
    static let supportedRange: ClosedRange<Double> = 0.1...0.9

    /// Default UI sensitivity that preserves the legacy detector threshold of 0.3.
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

    static func clamped(_ value: Double) -> Double {
        min(max(value, supportedRange.lowerBound), supportedRange.upperBound)
    }
}
