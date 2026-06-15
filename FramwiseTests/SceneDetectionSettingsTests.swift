//
//  SceneDetectionSettingsTests.swift
//  FramwiseTests
//

import XCTest
import AVFoundation
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

    // MARK: - Auto Sensitivity

    func testAutoSensitivity_boundaries() {
        XCTAssertEqual(SceneDetectionSettings.autoSensitivity(forTargetCount: 12), 0.3, accuracy: 0.0001)
        XCTAssertEqual(SceneDetectionSettings.autoSensitivity(forTargetCount: 120), 0.9, accuracy: 0.0001)
    }

    func testAutoSensitivity_midRange() {
        let mid = SceneDetectionSettings.autoSensitivity(forTargetCount: 66)
        XCTAssertEqual(mid, 0.6, accuracy: 0.01)
    }

    func testAutoSensitivity_clampsOutOfRange() {
        XCTAssertEqual(SceneDetectionSettings.autoSensitivity(forTargetCount: 0), 0.3, accuracy: 0.0001)
        XCTAssertEqual(SceneDetectionSettings.autoSensitivity(forTargetCount: 200), 0.9, accuracy: 0.0001)
    }

    // MARK: - Media Decode Guardrails

    func testRequireDecodableFrames_throwsWhenNoFramesDecoded() {
        XCTAssertThrowsError(try SceneDetector.requireDecodableFrames(0)) { error in
            XCTAssertEqual(error as? SceneDetectorError, .noDecodableFrames)
            XCTAssertEqual(error.localizedDescription, "No decodable video frames found")
        }
    }

    func testRequireDecodableFrames_allowsDecodedFrames() {
        XCTAssertNoThrow(try SceneDetector.requireDecodableFrames(1))
    }

    func testPublicFrameSkipReason_doesNotExposeUnderlyingFilePath() {
        let path = "/Users/editor/Private Footage/client/reel.mov"
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: -11800,
            userInfo: [
                NSFilePathErrorKey: path,
                NSLocalizedDescriptionKey: "The file at \(path) could not be decoded."
            ]
        )

        let reason = SceneDetector.publicFrameSkipReason(for: error)

        XCTAssertTrue(reason.contains("domain=\(AVFoundationErrorDomain)"))
        XCTAssertTrue(reason.contains("code=-11800"))
        XCTAssertFalse(reason.contains(path))
        XCTAssertFalse(reason.contains("/Users/editor"))
        XCTAssertFalse(reason.contains("Private Footage"))
        XCTAssertFalse(reason.contains("reel.mov"))
        XCTAssertFalse(reason.contains("The file at"))
    }
}
