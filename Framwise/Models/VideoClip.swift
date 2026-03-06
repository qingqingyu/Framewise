//
//  VideoClip.swift
//  Framwise
//
//  Represents a single clip segment from a video file
//

import Foundation
import AVFoundation
import CoreImage

struct VideoClip: Identifiable, Hashable {
    let id: UUID
    let sourceFileURL: URL
    let sourceFileName: String
    let timecodeStart: CMTime          // 入点
    let timecodeEnd: CMTime            // 出点
    let thumbnailTimes: [CMTime]       // 缩略图时间点

    var isSelected: Bool = false

    init(
        id: UUID = UUID(),
        sourceFileURL: URL,
        timecodeStart: CMTime,
        timecodeEnd: CMTime,
        thumbnailTimes: [CMTime] = []
    ) {
        self.id = id
        self.sourceFileURL = sourceFileURL
        self.sourceFileName = sourceFileURL.lastPathComponent
        self.timecodeStart = timecodeStart
        self.timecodeEnd = timecodeEnd
        self.thumbnailTimes = thumbnailTimes.isEmpty
            ? Self.generateThumbnailTimes(start: timecodeStart, end: timecodeEnd)
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
