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
        // Total frames as if running at nominal rate
        var totalFrames = Int(round(seconds * nominalRate))

        // Drop-frame correction:
        // Every minute (except every 10th), drop `dropFrames` frames
        let dropFrames = nominalRate == 60.0 ? 4 : 2

        let framesPer10min = Int(nominalRate) * 600  // 18000 for 30fps
        let framesPer1min = Int(nominalRate) * 60     // 1800 for 30fps

        // Number of 10-minute blocks
        let tenMinBlocks = totalFrames / framesPer10min
        totalFrames -= tenMinBlocks * (9 * dropFrames)

        // Remaining frames within the current 10-minute block
        let remaining = totalFrames - tenMinBlocks * framesPer10min

        if remaining > 0 {
            // Number of full minutes within the 10-min block (the first minute is index 0, doesn't drop)
            let oneMinBlocks = (remaining - 1) / framesPer1min
            totalFrames -= oneMinBlocks * dropFrames
        }

        let ff = totalFrames % Int(nominalRate)
        let totalSecs = totalFrames / Int(nominalRate)
        let ss = totalSecs % 60
        let mm = (totalSecs / 60) % 60
        let hh = totalSecs / 3600

        return String(format: "%02d:%02d:%02d;%02d", hh, mm, ss, ff)
    }
}
