//
//  TimecodeUtils.swift
//  Framwise
//
//  Timecode formatting and conversion utilities
//

import Foundation
import AVFoundation

enum TimecodeUtils {
    /// Standard frame rates
    static let standardFrameRates: [Double] = [23.976, 24, 25, 29.97, 30, 50, 59.94, 60]

    /// Format CMTime to HH:MM:SS:FF display string
    static func formatTimecode(_ time: CMTime, frameRate: Double = 24) -> String {
        let totalSeconds = CMTimeGetSeconds(time)
        return formatTimecode(seconds: totalSeconds, frameRate: frameRate)
    }

    /// Format seconds to HH:MM:SS:FF display string
    static func formatTimecode(seconds: Double, frameRate: Double = 24) -> String {
        guard seconds >= 0 else { return "00:00:00:00" }

        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int((seconds.truncatingRemainder(dividingBy: 60)))
        let frames = Int(((seconds.truncatingRemainder(dividingBy: 1)) * frameRate))

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frames)
    }

    /// Format CMTime to EDL timecode (HH:MM:SS:FF, 6 digits for hours)
    static func formatTimecodeEDL(_ time: CMTime, frameRate: Double = 24) -> String {
        let totalSeconds = CMTimeGetSeconds(time)
        return formatTimecode(seconds: totalSeconds, frameRate: frameRate)
    }

    /// Format seconds to simple MM:SS display
    static func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Parse timecode string (HH:MM:SS:FF) to CMTime
    static func parseTimecode(_ string: String, frameRate: Double = 24) -> CMTime? {
        let components = string.split(separator: ":").map { Double($0) }
        guard components.count == 4,
              let hours = components[0],
              let minutes = components[1],
              let seconds = components[2],
              let frames = components[3] else {
            return nil
        }

        let totalSeconds = hours * 3600 + minutes * 60 + seconds + frames / frameRate
        return CMTime(seconds: totalSeconds, preferredTimescale: 600)
    }

    /// Calculate frame number from CMTime
    static func frameNumber(from time: CMTime, frameRate: Double = 24) -> Int {
        Int(CMTimeGetSeconds(time) * frameRate)
    }

    /// Calculate CMTime from frame number
    static func time(from frameNumber: Int, frameRate: Double = 24) -> CMTime {
        CMTime(seconds: Double(frameNumber) / frameRate, preferredTimescale: 600)
    }

    /// Convert between frame rates (reel time)
    static func convertTimecode(
        _ time: CMTime,
        from sourceRate: Double,
        to targetRate: Double
    ) -> CMTime {
        let seconds = CMTimeGetSeconds(time)
        let frameNumber = seconds * sourceRate
        let targetSeconds = frameNumber / targetRate
        return CMTime(seconds: targetSeconds, preferredTimescale: 600)
    }
}

// MARK: - Drop Frame Support

extension TimecodeUtils {
    /// Check if frame rate is drop frame
    static func isDropFrame(_ frameRate: Double) -> Bool {
        // 29.97 and 59.94 are drop frame rates
        return abs(frameRate - 29.97) < 0.01 || abs(frameRate - 59.94) < 0.01
    }

    /// Format drop frame timecode (uses ; instead of : before frames)
    /// Correctly accounts for dropped frames in 29.97fps and 59.94fps
    static func formatDropFrameTimecode(seconds: Double, frameRate: Double = 29.97) -> String {
        let isDrop = isDropFrame(frameRate)

        if !isDrop {
            return formatTimecode(seconds: seconds, frameRate: frameRate)
        }

        // Nominal frame rate (30 or 60) — what the timecode counts in
        let nominalRate = round(frameRate)  // 30.0 or 60.0
        let nominalInt = Int(nominalRate)

        // Total frames as if running at nominal rate
        let rawFrames = Int(round(seconds * nominalRate))

        // Drop-frame correction:
        // Every minute (except every 10th), skip `dropFrames` frame numbers
        let dropFrames = nominalRate == 60.0 ? 4 : 2
        let framesPer10min = nominalInt * 600  // 18000 for 30fps
        let framesPer1min = nominalInt * 60     // 1800 for 30fps

        // Step 1: How many complete 10-minute blocks?
        let tenMinBlocks = rawFrames / framesPer10min
        // Each 10-min block drops 9 * dropFrames (minutes 1-9 drop, minute 0 doesn't)
        let droppedBy10Min = tenMinBlocks * 9 * dropFrames

        // Step 2: Frames remaining within the current (partial) 10-minute block
        let remainingInBlock = rawFrames % framesPer10min

        // Step 3: Within that remainder, how many full 1-minute intervals?
        // Minute 0 doesn't drop, minutes 1-9 each drop `dropFrames`
        let oneMinBlocks = remainingInBlock / framesPer1min
        // If we're past minute 0, each completed minute drops `dropFrames`
        let droppedInBlock = max(0, oneMinBlocks - 1) * dropFrames

        // Step 4: Timecode frame number = raw frames - all dropped frames
        var tcFrames = rawFrames - droppedBy10Min - droppedInBlock

        let ff = tcFrames % nominalInt
        tcFrames /= nominalInt
        let ss = tcFrames % 60
        tcFrames /= 60
        let mm = tcFrames % 60
        let hh = tcFrames / 60

        return String(format: "%02d:%02d:%02d;%02d", hh, mm, ss, ff)
    }
}
