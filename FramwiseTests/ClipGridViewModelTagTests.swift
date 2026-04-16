//
//  ClipGridViewModelTagTests.swift
//  FramwiseTests
//

import XCTest
@testable import Framwise
import AVFoundation

@MainActor
final class ClipGridViewModelTagTests: XCTestCase {

    var vm: ClipGridViewModel!

    override func setUp() {
        vm = ClipGridViewModel()
    }

    override func tearDown() {
        vm = nil
    }

    private func makeClip(name: String, tagIDs: Set<UUID> = []) -> VideoClip {
        var clip = VideoClip(
            sourceFileURL: URL(fileURLWithPath: "/tmp/\(name)"),
            timecodeStart: .zero,
            timecodeEnd: CMTime(seconds: 5, preferredTimescale: 600)
        )
        clip.tagIDs = tagIDs
        return clip
    }

    // MARK: - Tag Filtering

    func testFilteredClips_tagFilter_returnsOnlyTaggedClips() {
        let tagID = UUID()
        let clip1 = makeClip(name: "a.mov", tagIDs: [tagID])
        let clip2 = makeClip(name: "b.mov")
        let result = vm.filteredClips(from: [clip1, clip2], tagFilter: tagID)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, clip1.id)
    }

    func testFilteredClips_tagFilterNil_returnsAll() {
        let tagID = UUID()
        let clip1 = makeClip(name: "a.mov", tagIDs: [tagID])
        let clip2 = makeClip(name: "b.mov")
        let result = vm.filteredClips(from: [clip1, clip2], tagFilter: nil)
        XCTAssertEqual(result.count, 2)
    }

    func testFilteredClips_tagFilter_noMatches_returnsEmpty() {
        let clip = makeClip(name: "a.mov")
        let result = vm.filteredClips(from: [clip], tagFilter: UUID())
        XCTAssertTrue(result.isEmpty)
    }

    func testFilteredClips_tagFilter_combinedWithHideWaste() {
        let tagID = UUID()
        var clip1 = makeClip(name: "a.mov", tagIDs: [tagID])
        clip1.wasteType = .blackout
        let clip2 = makeClip(name: "b.mov", tagIDs: [tagID])
        let result = vm.filteredClips(from: [clip1, clip2], tagFilter: tagID, hideWaste: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, clip2.id)
    }

    func testFilteredClips_tagFilter_emptyClips_returnsEmpty() {
        let result = vm.filteredClips(from: [], tagFilter: UUID())
        XCTAssertTrue(result.isEmpty)
    }

    func testFilteredClips_tagFilter_combinedWithSourceURL() {
        let tagID = UUID()
        let urlA = URL(fileURLWithPath: "/tmp/a.mov")
        let urlB = URL(fileURLWithPath: "/tmp/b.mov")
        var clip1 = VideoClip(sourceFileURL: urlA, timecodeStart: .zero, timecodeEnd: CMTime(seconds: 5, preferredTimescale: 600))
        clip1.tagIDs = [tagID]
        var clip2 = VideoClip(sourceFileURL: urlB, timecodeStart: .zero, timecodeEnd: CMTime(seconds: 5, preferredTimescale: 600))
        clip2.tagIDs = [tagID]

        let result = vm.filteredClips(from: [clip1, clip2], sourceURL: urlA, tagFilter: tagID)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.sourceFileURL, urlA)
    }

    // MARK: - groupedClips propagates tagFilter

    func testGroupedClips_propagatesTagFilter() {
        let tagID = UUID()
        let clip1 = makeClip(name: "a.mov", tagIDs: [tagID])
        let clip2 = makeClip(name: "b.mov")
        let groups = vm.groupedClips(from: [clip1, clip2], tagFilter: tagID)
        let allClips = groups.flatMap { $0.clips }
        XCTAssertEqual(allClips.count, 1)
    }

    // MARK: - Cache regression reproductions

    func testFilteredClips_recomputesWhenTagMembershipChangesUnderActiveTagFilter() {
        let tagID = UUID()
        let clip1 = makeClip(name: "a.mov")
        let clip2 = makeClip(name: "b.mov")

        let initial = vm.filteredClips(from: [clip1, clip2], tagFilter: tagID)
        XCTAssertTrue(initial.isEmpty)

        var updatedClip1 = clip1
        updatedClip1.tagIDs.insert(tagID)
        let refreshed = vm.filteredClips(from: [updatedClip1, clip2], tagFilter: tagID)

        XCTAssertEqual(refreshed.map(\.id), [updatedClip1.id])
    }

    func testFilteredClips_recomputesWhenWasteVisibilityChangesUnderHideWaste() {
        var clip1 = makeClip(name: "a.mov")
        let clip2 = makeClip(name: "b.mov")

        let initial = vm.filteredClips(from: [clip1, clip2], hideWaste: true)
        XCTAssertEqual(initial.map(\.id), [clip1.id, clip2.id])

        clip1.wasteType = .blackout
        let refreshed = vm.filteredClips(from: [clip1, clip2], hideWaste: true)

        XCTAssertEqual(refreshed.map(\.id), [clip2.id])
    }
}
