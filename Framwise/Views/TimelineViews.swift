//
//  TimelineViews.swift
//  Framwise
//
//  Collapsed timeline presentation components
//

import SwiftUI
import AVFoundation

// MARK: - Collapsed Timeline View

struct CollapsedTimelineView: View {
    let groups: [(sourceURL: URL, clips: [VideoClip])]
    let selectedClipIDs: Set<UUID>
    let onClipTap: (VideoClip) -> Void

    @State private var hoveredClipID: UUID?

    // Computed properties
    private var allClips: [VideoClip] {
        groups.flatMap { $0.clips }
    }

    private static let palette: [Color] = [
        FramwiseTheme.info,
        FramwiseTheme.success,
        FramwiseTheme.warning,
        FramwiseTheme.accent,
        Color(hex: "E58ACF"),
        Color(hex: "58C7D1"),
        Color(hex: "8EA6FF"),
        Color(hex: "7DDDB8"),
        FramwiseTheme.danger,
        FramwiseTheme.warm,
        Color(hex: "4FA89B"),
        Color(hex: "A77A5B")
    ]

    private var fileColorMap: [URL: Color] {
        Dictionary(uniqueKeysWithValues:
            groups.enumerated().map { ($0.element.sourceURL, Self.palette[$0.offset % Self.palette.count]) }
        )
    }

    var body: some View {
        if allClips.isEmpty {
            FramwiseStatePanel(
                state: .empty,
                title: "Sequence map empty",
                message: "Current filters leave no clips for the timeline.",
                systemImage: "timeline.selection",
                compact: true
            )
        } else if groups.count <= 1 {
            // Single source: use original single-track layout
            singleTrackContent
        } else {
            // Multi-source: stack per-source tracks
            multiTrackContent
        }
    }

    // MARK: - Single Track (1 source)

    private var maxTime: Double {
        max(allClips.map { CMTimeGetSeconds($0.timecodeEnd) }.max() ?? 1, 0.001)
    }

    private var singleTrackContent: some View {
        TimelineGeometryReader(
            allClips: allClips,
            maxTime: maxTime,
            fileColorMap: fileColorMap,
            selectedClipIDs: selectedClipIDs,
            hoveredClipID: hoveredClipID,
            onClipTap: onClipTap,
            onHover: { clipID, hovering in
                hoveredClipID = hovering ? clipID : nil
            }
        )
        .frame(height: 24)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline navigation with \(allClips.count) clips")
    }

    // MARK: - Multi Track (per-source)

    private var multiTrackContent: some View {
        VStack(spacing: 8) {
            ForEach(groups, id: \.sourceURL) { group in
                let groupMaxTime = max(group.clips.map { CMTimeGetSeconds($0.timecodeEnd) }.max() ?? 1, 0.001)
                HStack(spacing: 10) {
                    Text(group.sourceURL.deletingPathExtension().lastPathComponent.uppercased())
                        .font(.framwiseMono(9))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(width: 120, alignment: .leading)
                        .background(
                            Capsule(style: .continuous)
                                .fill(FramwiseTheme.surfaceRaised)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(FramwiseTheme.line.opacity(0.7), lineWidth: 1)
                        )

                    TimelineGeometryReader(
                        allClips: group.clips,
                        maxTime: groupMaxTime,
                        fileColorMap: fileColorMap,
                        selectedClipIDs: selectedClipIDs,
                        hoveredClipID: hoveredClipID,
                        onClipTap: onClipTap,
                        onHover: { clipID, hovering in
                            hoveredClipID = hovering ? clipID : nil
                        }
                    )
                    .frame(height: 18)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline navigation with \(allClips.count) clips from \(groups.count) sources")
    }
}

// MARK: - Timeline Geometry Reader

struct TimelineGeometryReader: View {
    let allClips: [VideoClip]
    let maxTime: Double
    let fileColorMap: [URL: Color]
    let selectedClipIDs: Set<UUID>
    let hoveredClipID: UUID?
    let onClipTap: (VideoClip) -> Void
    let onHover: (UUID, Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            TimelineContent(
                allClips: allClips,
                maxTime: maxTime,
                fileColorMap: fileColorMap,
                selectedClipIDs: selectedClipIDs,
                hoveredClipID: hoveredClipID,
                width: geometry.size.width,
                onClipTap: onClipTap,
                onHover: onHover
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline with \(allClips.count) clips")
    }
}

struct TimelineContent: View {
    let allClips: [VideoClip]
    let maxTime: Double
    let fileColorMap: [URL: Color]
    let selectedClipIDs: Set<UUID>
    let hoveredClipID: UUID?
    let width: CGFloat
    let onClipTap: (VideoClip) -> Void
    let onHover: (UUID, Bool) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(FramwiseTheme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(FramwiseTheme.line.opacity(0.55), lineWidth: 1)
                )

            Group {
                ForEach(allClips) { clip in
                    ClipBlockView(
                        clip: clip,
                        maxTime: maxTime,
                        totalWidth: width,
                        color: fileColorMap[clip.sourceFileURL] ?? .gray,
                        isSelected: selectedClipIDs.contains(clip.id),
                        isHovered: hoveredClipID == clip.id,
                        onTap: { onClipTap(clip) },
                        onHover: { hovering in
                            onHover(clip.id, hovering)
                        }
                    )
                }
            }

            TimeMarkersView(totalDuration: maxTime, width: width)
        }
    }
}

// MARK: - Clip Block View

struct ClipBlockView: View {
    let clip: VideoClip
    let maxTime: Double
    let totalWidth: CGFloat
    let color: Color
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    private var startRatio: Double {
        CMTimeGetSeconds(clip.timecodeStart) / maxTime
    }

    private var endRatio: Double {
        CMTimeGetSeconds(clip.timecodeEnd) / maxTime
    }

    private var blockWidth: CGFloat {
        max((endRatio - startRatio) * totalWidth, 2)
    }

    private var xOffset: CGFloat {
        startRatio * totalWidth
    }

    private var fillColor: Color {
        if isSelected {
            return FramwiseTheme.accent
        } else if isHovered {
            return color.opacity(0.9)
        } else {
            return color.opacity(0.6)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fillColor)
            .frame(width: blockWidth, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? FramwiseTheme.warm.opacity(0.7) : Color.clear, lineWidth: 1)
            )
            .offset(x: xOffset)
            .onHover { hovering in
                onHover(hovering)
            }
            .onTapGesture {
                onTap()
            }
            .help("\(clip.sourceFileName): \(clip.timecodeStartString) - \(clip.timecodeEndString)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Clip from \(clip.sourceFileName), \(clip.timecodeStartString) to \(clip.timecodeEndString)")
            .accessibilityHint(isSelected ? "Selected. Double-click to deselect." : "Not selected. Double-click to select.")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Time Markers View

struct TimeMarkersView: View {
    let totalDuration: Double
    let width: CGFloat

    private var markerCount: Int {
        min(Int(totalDuration / 60), 6) + 1
    }

    private var interval: Double {
        totalDuration / Double(markerCount)
    }

    var body: some View {
        Group {
            ForEach(0...markerCount, id: \.self) { index in
                TimeMarkerView(
                    time: Double(index) * interval,
                    totalDuration: totalDuration,
                    width: width
                )
            }
        }
    }
}

struct TimeMarkerView: View {
    let time: Double
    let totalDuration: Double
    let width: CGFloat

    private var xPos: CGFloat {
        (time / totalDuration) * width - 15
    }

    private var timeText: String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return mins > 0 ? "\(mins):\(String(format: "%02d", secs))" : "\(secs)s"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(timeText)
                .font(.framwiseMono(8))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.75))
            Rectangle()
                .fill(FramwiseTheme.line.opacity(0.8))
                .frame(width: 1, height: 4)
        }
        .offset(x: xPos)
    }
}
