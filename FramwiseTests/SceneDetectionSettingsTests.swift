//
//  SceneDetectionSettingsTests.swift
//  FramwiseTests
//

import XCTest
@testable import Framwise

final class SceneDetectionSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "SceneDetectionSettingsTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testThresholdForUISensitivity_invertsUserFacingControl() {
        XCTAssertEqual(SceneDetectionSettings.threshold(forUISensitivity: 0.1), 0.9, accuracy: 0.0001)
        XCTAssertEqual(SceneDetectionSettings.threshold(forUISensitivity: 0.7), 0.3, accuracy: 0.0001)
        XCTAssertEqual(SceneDetectionSettings.threshold(forUISensitivity: 0.9), 0.1, accuracy: 0.0001)
    }

    func testDefaultUISensitivity_preservesLegacyThreshold() {
        XCTAssertEqual(
            SceneDetectionSettings.threshold(forUISensitivity: SceneDetectionSettings.defaultUISensitivity),
            0.3,
            accuracy: 0.0001
        )
    }

    func testMigrateStoredSensitivityIfNeeded_invertsExistingValueOnce() {
        defaults.set(0.2, forKey: SceneDetectionSettings.sensitivityKey)

        SceneDetectionSettings.migrateStoredSensitivityIfNeeded(userDefaults: defaults)
        XCTAssertEqual(defaults.double(forKey: SceneDetectionSettings.sensitivityKey), 0.8, accuracy: 0.0001)

        SceneDetectionSettings.migrateStoredSensitivityIfNeeded(userDefaults: defaults)
        XCTAssertEqual(defaults.double(forKey: SceneDetectionSettings.sensitivityKey), 0.8, accuracy: 0.0001)
    }

    func testMigrateStoredSensitivityIfNeeded_doesNotCreateValueWhenUnset() {
        SceneDetectionSettings.migrateStoredSensitivityIfNeeded(userDefaults: defaults)

        XCTAssertNil(defaults.object(forKey: SceneDetectionSettings.sensitivityKey))
        XCTAssertTrue(defaults.bool(forKey: SceneDetectionSettings.didMigrateSensitivityKey))
    }
}
