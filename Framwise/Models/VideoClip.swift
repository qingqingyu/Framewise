//
//  VideoClip.swift
//  Framwise
//
//  Represents a single clip segment from a video file
//

import Foundation
import AVFoundation
import CoreImage

// MARK: - CMTime Codable

extension CMTime: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let value = try container.decode(Int64.self)
        let timescale = try container.decode(Int32.self)
        // Backward compatibility: old format had only value+timescale (2 fields)
        // New format adds flags+epoch (4 fields)
        if !container.isAtEnd {
            let flags = try container.decode(UInt32.self)
            let epoch = try container.decode(Int64.self)
            self = CMTime(value: value, timescale: timescale, flags: CMTimeFlags(rawValue: flags), epoch: epoch)
        } else {
            self = CMTime(value: value, timescale: timescale)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value)
        try container.encode(timescale)
        try container.encode(flags.rawValue)
        try container.encode(epoch)
    }
}

enum WasteType: String, CaseIterable, Codable {
    case none = "None"
    case blackout = "Blackout"     // 黑屏
    case dark = "Dark"             // 极暗
    case solid = "Solid"           // 纯色/地面
}

struct VideoClip: Identifiable, Hashable {
    let id: UUID
    let sourceFileURL: URL
    let sourceFileName: String
    let timecodeStart: CMTime          // 入点
    let timecodeEnd: CMTime            // 出点
    let thumbnailTimes: [CMTime]       // 缩略图时间点

    var isSelected: Bool = false
    var wasteType: WasteType = .none
    var tagIDs: Set<UUID> = []

    init(
        id: UUID = UUID(),
        sourceFileURL: URL,
        timecodeStart: CMTime,
        timecodeEnd: CMTime,
        thumbnailTimes: [CMTime] = [],
        wasteType: WasteType = .none
    ) {
        self.id = id
        self.sourceFileURL = sourceFileURL
        self.sourceFileName = sourceFileURL.lastPathComponent
        self.timecodeStart = timecodeStart
        self.timecodeEnd = timecodeEnd
        self.wasteType = wasteType
        let dur = CMTimeGetSeconds(timecodeEnd) - CMTimeGetSeconds(timecodeStart)
        let count = Self.thumbnailCount(forDuration: dur)
        self.thumbnailTimes = thumbnailTimes.isEmpty
            ? Self.generateThumbnailTimes(start: timecodeStart, end: timecodeEnd, count: count)
            : thumbnailTimes
    }

    /// Duration in seconds
    var duration: Double {
        CMTimeGetSeconds(timecodeEnd) - CMTimeGetSeconds(timecodeStart)
    }

    /// Formatted duration string (MM:SS, or X.Xs for sub-second)
    var durationString: String {
        if duration < 1 {
            return String(format: "%.1fs", duration)
        }
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Timecode string for display (HH:MM:SS:FF)
    var timecodeStartString: String {
        TimecodeUtils.formatTimecode(timecodeStart)
    }

    var timecodeEndString: String {
        TimecodeUtils.formatTimecode(timecodeEnd)
    }

    /// Determine thumbnail count based on clip duration
    static func thumbnailCount(forDuration duration: Double) -> Int {
        switch duration {
        case ..<3: return 1
        case 3..<10: return 2
        case 10..<30: return 3
        case 30..<60: return 4
        default: return 5
        }
    }

    /// Generate evenly spaced thumbnail times for this clip
    private static func generateThumbnailTimes(start: CMTime, end: CMTime, count: Int = 5) -> [CMTime] {
        let duration = CMTimeGetSeconds(end) - CMTimeGetSeconds(start)
        guard duration > 0 else { return [start] }

        let interval = duration / Double(count + 1)
        return (1...count).map { index in
            let offset = Double(index) * interval
            return CMTimeAdd(start, CMTime(seconds: offset, preferredTimescale: 600))
        }
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: VideoClip, rhs: VideoClip) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - VideoClip Codable

extension VideoClip: Codable {
    enum CodingKeys: String, CodingKey {
        case id, sourceFileURL, timecodeStart, timecodeEnd
        case wasteType, tagIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceFileURL = try c.decode(URL.self, forKey: .sourceFileURL)
        timecodeStart = try c.decode(CMTime.self, forKey: .timecodeStart)
        timecodeEnd = try c.decode(CMTime.self, forKey: .timecodeEnd)
        wasteType = try c.decodeIfPresent(WasteType.self, forKey: .wasteType) ?? .none
        tagIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .tagIDs) ?? []

        sourceFileName = sourceFileURL.lastPathComponent
        isSelected = false
        let dur = CMTimeGetSeconds(timecodeEnd) - CMTimeGetSeconds(timecodeStart)
        let count = Self.thumbnailCount(forDuration: dur)
        thumbnailTimes = Self.generateThumbnailTimes(
            start: timecodeStart, end: timecodeEnd, count: count
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceFileURL, forKey: .sourceFileURL)
        try c.encode(timecodeStart, forKey: .timecodeStart)
        try c.encode(timecodeEnd, forKey: .timecodeEnd)
        if wasteType != .none {
            try c.encode(wasteType, forKey: .wasteType)
        }
        if !tagIDs.isEmpty {
            try c.encode(tagIDs, forKey: .tagIDs)
        }
    }
}

// MARK: - Clip Creation Info

struct ClipSegment {
    let sourceURL: URL
    let startTime: CMTime
    let endTime: CMTime

    func toVideoClip() -> VideoClip {
        VideoClip(
            sourceFileURL: sourceURL,
            timecodeStart: startTime,
            timecodeEnd: endTime
        )
    }
}
