//
//  VideoClip.swift
//  Framwise
//
//  Represents a single clip segment from a video file
//

import Foundation
import AVFoundation
import CoreImage

enum WasteType: String, CaseIterable {
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

    /// Formatted duration string (MM:SS)
    var durationString: String {
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
