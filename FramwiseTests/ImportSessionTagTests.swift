//
//  ImportSessionTagTests.swift
//  FramwiseTests
//

import XCTest
@testable import Framwise
import AVFoundation

@MainActor
final class ImportSessionTagTests: XCTestCase {

    var session: ImportSession!

    override func setUp() {
        session = ImportSession()
    }

    override func tearDown() {
        session = nil
    }

    // MARK: - Helpers

    private func makeClip(name: String) -> VideoClip {
        VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 5, preferredTimescale: 600)
        )
    }

    // MARK: - addTag

    func testAddTag_appendsTag() {
        let tag = ClipTag(name: "Ceremony", color: .purple)
        session.addTag(tag)
        XCTAssertEqual(session.tags.count, 1)
        XCTAssertEqual(session.tags.first?.name, "Ceremony")
    }

    func testAddTag_multipleTags() {
        session.addTag(ClipTag(name: "A", color: .red))
        session.addTag(ClipTag(name: "B", color: .blue))
        XCTAssertEqual(session.tags.count, 2)
    }

    // MARK: - removeTag

    func testRemoveTag_removesFromTagsArray() {
        let tag = ClipTag(name: "ToDelete", color: .red)
        session.addTag(tag)
        session.removeTag(tag.id)
        XCTAssertTrue(session.tags.isEmpty)
    }

    func testRemoveTag_removesTagFromAllClips() {
        let tag = ClipTag(name: "T", color: .blue)
        session.addTag(tag)
        let clip1 = makeClip(name: "a.mov")
        let clip2 = makeClip(name: "b.mov")
        session.addClip(clip1)
        session.addClip(clip2)
        session.assignTag(tag.id, to: clip1.id)
        session.assignTag(tag.id, to: clip2.id)

        session.removeTag(tag.id)

        XCTAssertTrue(session.allClips[0].tagIDs.isEmpty)
        XCTAssertTrue(session.allClips[1].tagIDs.isEmpty)
    }

    func testRemoveTag_resetsActiveTagFilter() {
        let tag = ClipTag(name: "Filtered", color: .green)
        session.addTag(tag)
        session.activeTagFilter = tag.id

        session.removeTag(tag.id)

        XCTAssertNil(session.activeTagFilter)
    }

    func testRemoveTag_nonexistentID_isNoOp() {
        session.addTag(ClipTag(name: "Keep", color: .red))
        session.removeTag(UUID())
        XCTAssertEqual(session.tags.count, 1)
    }

    // MARK: - renameTag

    func testRenameTag_updatesName() {
        let tag = ClipTag(name: "Old", color: .red)
        session.addTag(tag)
        session.renameTag(tag.id, to: "New")
        XCTAssertEqual(session.tags.first?.name, "New")
    }

    func testRenameTag_nonexistentID_isNoOp() {
        let tag = ClipTag(name: "Stay", color: .blue)
        session.addTag(tag)
        session.renameTag(UUID(), to: "Changed")
        XCTAssertEqual(session.tags.first?.name, "Stay")
    }

    // MARK: - assignTag / removeTag(from:)

    func testAssignTag_addsTagIDToClip() {
        let tag = ClipTag(name: "T", color: .red)
        let clip = makeClip(name: "a.mov")
        session.addClip(clip)
        session.assignTag(tag.id, to: clip.id)
        XCTAssertTrue(session.allClips[0].tagIDs.contains(tag.id))
    }

    func testAssignTag_isIdempotent() {
        let tag = ClipTag(name: "T", color: .blue)
        let clip = makeClip(name: "a.mov")
        session.addClip(clip)
        session.assignTag(tag.id, to: clip.id)
        session.assignTag(tag.id, to: clip.id)
        XCTAssertEqual(session.allClips[0].tagIDs.count, 1)
    }

    func testRemoveTagFromClip_removesTagID() {
        let tag = ClipTag(name: "T", color: .green)
        let clip = makeClip(name: "a.mov")
        session.addClip(clip)
        session.assignTag(tag.id, to: clip.id)
        session.removeTag(tag.id, from: clip.id)
        XCTAssertTrue(session.allClips[0].tagIDs.isEmpty)
    }

    func testRemoveTagFromClip_nonexistentClip_isNoOp() {
        let tag = ClipTag(name: "T", color: .red)
        let clip = makeClip(name: "a.mov")
        session.addClip(clip)
        session.assignTag(tag.id, to: clip.id)
        session.removeTag(tag.id, from: UUID())
        XCTAssertTrue(session.allClips[0].tagIDs.contains(tag.id))
    }

    // MARK: - clipsWithTag / clipCount

    func testClipsWithTag_returnsMatchingClips() {
        let tag = ClipTag(name: "T", color: .red)
        let clip1 = makeClip(name: "a.mov")
        let clip2 = makeClip(name: "b.mov")
        session.addClip(clip1)
        session.addClip(clip2)
        session.assignTag(tag.id, to: clip1.id)

        let result = session.clipsWithTag(tag.id)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, clip1.id)
    }

    func testClipsWithTag_noMatches_returnsEmpty() {
        let result = session.clipsWithTag(UUID())
        XCTAssertTrue(result.isEmpty)
    }

    func testClipCount_returnsCorrectCount() {
        let tag = ClipTag(name: "T", color: .purple)
        session.addClip(makeClip(name: "a.mov"))
        session.addClip(makeClip(name: "b.mov"))
        session.addClip(makeClip(name: "c.mov"))
        session.assignTag(tag.id, to: session.allClips[0].id)
        session.assignTag(tag.id, to: session.allClips[2].id)

        XCTAssertEqual(session.clipCount(for: tag.id), 2)
    }

    func testClipCount_matchesClipsWithTagCount() {
        let tag = ClipTag(name: "T", color: .orange)
        session.addClip(makeClip(name: "a.mov"))
        session.addClip(makeClip(name: "b.mov"))
        session.assignTag(tag.id, to: session.allClips[0].id)

        XCTAssertEqual(session.clipCount(for: tag.id), session.clipsWithTag(tag.id).count)
    }

    // MARK: - Wedding Preset

    func testWeddingPresetTags_returnsSixTags() {
        let tags = ImportSession.weddingPresetTags()
        XCTAssertEqual(tags.count, 6)
    }

    func testWeddingPresetTags_expectedNames() {
        let tags = ImportSession.weddingPresetTags()
        let names = Set(tags.map { $0.name })
        XCTAssertTrue(names.contains("新娘准备"))
        XCTAssertTrue(names.contains("新郎准备"))
        XCTAssertTrue(names.contains("仪式"))
        XCTAssertTrue(names.contains("晚宴"))
        XCTAssertTrue(names.contains("第一支舞"))
        XCTAssertTrue(names.contains("花絮"))
    }

    func testLoadWeddingPreset_addsAllToEmptySession() {
        session.loadWeddingPreset()
        XCTAssertEqual(session.tags.count, 6)
    }

    func testLoadWeddingPreset_skipsDuplicateNames() {
        session.addTag(ClipTag(name: "仪式", color: .red))
        session.loadWeddingPreset()
        XCTAssertEqual(session.tags.count, 6)
        let existingTag = session.tags.first { $0.name == "仪式" }
        XCTAssertEqual(existingTag?.color, .red)
    }

    func testLoadWeddingPreset_idempotent() {
        session.loadWeddingPreset()
        session.loadWeddingPreset()
        XCTAssertEqual(session.tags.count, 6)
    }

    // MARK: - clear resets tags

    func testClear_resetsTagsAndFilter() {
        session.addTag(ClipTag(name: "T", color: .red))
        session.activeTagFilter = UUID()
        session.addClip(makeClip(name: "a.mov"))
        session.clear()
        XCTAssertTrue(session.tags.isEmpty)
        XCTAssertNil(session.activeTagFilter)
        XCTAssertTrue(session.allClips.isEmpty)
    }

    // MARK: - VideoClip default tagIDs

    func testVideoClip_defaultTagIDsIsEmpty() {
        let clip = makeClip(name: "test.mov")
        XCTAssertTrue(clip.tagIDs.isEmpty)
    }
}
