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

    /// Format CMTime to EDL timecode (HH:MM:SS:FF or HH:MM:SS;FF for drop-frame)
    /// Automatically uses drop-frame format for 29.97/59.94fps
    static func formatTimecodeEDL(_ time: CMTime, frameRate: Double = 24) -> String {
        let totalSeconds = CMTimeGetSeconds(time)
        if isDropFrame(frameRate) {
            return formatDropFrameTimecode(seconds: totalSeconds, frameRate: frameRate)
        }
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
    /// Correctly accounts for dropped frame numbers in 29.97fps and 59.94fps
    ///
    /// Standard SMPTE drop-frame algorithm:
    /// 1. Convert seconds → actual frame count at the real rate (29.97fps)
    /// 2. Count how many frame numbers have been dropped (skipped) up to this point
    /// 3. Timecode number = actual frames + dropped frame numbers
    ///
    /// For 29.97fps: every minute except every 10th, 2 frame numbers are skipped
    /// For 59.94fps: every minute except every 10th, 4 frame numbers are skipped
    static func formatDropFrameTimecode(seconds: Double, frameRate: Double = 29.97) -> String {
        guard isDropFrame(frameRate) else {
            return formatTimecode(seconds: seconds, frameRate: frameRate)
        }

        let nominalInt = Int(round(frameRate))  // 30 or 60
        let dropFrames = nominalInt == 60 ? 4 : 2

        // Actual frame count at the real frame rate
        let actualFrames = Int(round(seconds * frameRate))

        // DF-aware frame counts:
        // Within each 10-minute cycle: minute 0 has no drops, minutes 1-9 each drop
        let framesPer10Min = nominalInt * 600 - 9 * dropFrames  // e.g., 17982 for 29.97fps
        let framesPer1Min = nominalInt * 60 - dropFrames         // e.g., 1798 for 29.97fps

        let tenMinBlocks = actualFrames / framesPer10Min
        let remaining = actualFrames % framesPer10Min

        // Within the 10-min block, count how many drop-minutes we've passed
        let oneMinBlocks: Int
        if remaining >= dropFrames {
            oneMinBlocks = (remaining - dropFrames) / framesPer1Min
        } else {
            oneMinBlocks = 0
        }

        let totalDrops = tenMinBlocks * 9 * dropFrames + oneMinBlocks * dropFrames
        var tcFrames = actualFrames + totalDrops

        let ff = tcFrames % nominalInt
        tcFrames /= nominalInt
        let ss = tcFrames % 60
        tcFrames /= 60
        let mm = tcFrames % 60
        let hh = tcFrames / 60

        return String(format: "%02d:%02d:%02d;%02d", hh, mm, ss, ff)
    }
}
