//
//  ClipCellView.swift
//  Framwise
//
//  Individual clip cell with animated thumbnail
//

import SwiftUI
import AVFoundation

struct ClipCellView: View {
    let clip: VideoClip
    let size: CGSize
    let isSelected: Bool
    let thumbnailGenerator: ThumbnailGenerator
    var tags: [ClipTag] = []
    var similarityGroupSize: Int = 0

    @State private var thumbnails: [CGImage] = []
    @State private var currentThumbnailIndex = 0
    @State private var isHovering = false
    @State private var isLoading = true
    @State private var isAnimating = false
    @State private var isVisible = false
    @State private var loadTask: Task<Void, Never>?

    private var isWaste: Bool { clip.wasteType != .none }
    private var displayTags: [ClipTag] { Array(tags.filter { clip.tagIDs.contains($0.id) }.prefix(4)) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let currentThumbnail = thumbnails[safe: currentThumbnailIndex] {
                        Image(nsImage: currentThumbnail.nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if isLoading {
                        Rectangle()
                            .fill(FramwiseTheme.surfaceRaised)
                            .overlay(
                                FramwiseLoadingIndicator(tint: FramwiseTheme.accent, diameter: 18)
                            )
                    } else {
                        Rectangle()
                            .fill(FramwiseTheme.surfaceRaised)
                            .overlay(
                                Image(systemName: "film")
                                    .font(.largeTitle)
                                    .foregroundStyle(FramwiseTheme.textMuted)
                            )
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .overlay(FramwiseTheme.monitorGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FramwiseTheme.accent, lineWidth: 2)
                        .frame(width: size.width, height: size.height)

                    VStack {
                        HStack {
                            statusBadge(
                                text: "SELECTED",
                                systemImage: "checkmark.circle.fill",
                                color: FramwiseTheme.accent
                            )
                            .padding(10)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                if isHovering && !isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FramwiseTheme.warm.opacity(0.45), lineWidth: 1)
                        .frame(width: size.width, height: size.height)
                }

                if isWaste {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    FramwiseTheme.danger.opacity(0.1),
                                    FramwiseTheme.danger.opacity(0.36)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size.width, height: size.height)

                    VStack {
                        HStack {
                            statusBadge(text: wasteLabel.uppercased(), systemImage: "trash.fill", color: FramwiseTheme.danger)
                                .padding(10)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                if similarityGroupSize >= 2 {
                    VStack {
                        HStack {
                            Spacer()
                            statusBadge(
                                text: "\(similarityGroupSize) TAKES",
                                systemImage: "square.on.square",
                                color: FramwiseTheme.info
                            )
                            .padding(10)
                        }
                        Spacer()
                    }
                }

                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(clip.durationString.uppercased())
                                    .font(.framwiseMono(10))
                                    .foregroundStyle(FramwiseTheme.warm)

                                Text(clip.timecodeStartString)
                                    .font(.framwiseMono(11))
                                    .foregroundStyle(.white)

                                if !displayTags.isEmpty {
                                    HStack(spacing: 5) {
                                        ForEach(displayTags) { tag in
                                            Circle()
                                                .fill(tag.color.systemColor)
                                                .frame(width: 7, height: 7)
                                        }
                                        if clip.tagIDs.count > 4 {
                                            Text("+\(clip.tagIDs.count - 4)")
                                                .font(.framwiseMono(10))
                                                .foregroundStyle(.white.opacity(0.9))
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 6) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.82))
                                Text(shortSourceName)
                                    .font(.framwiseMono(10))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.84), Color.black.opacity(0.0)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(14, corners: [.bottomLeft, .bottomRight])
                }
                .frame(width: size.width, height: size.height)
            }
            .shadow(color: .black.opacity(isHovering ? 0.34 : 0.24), radius: isHovering ? 18 : 12, y: isHovering ? 10 : 6)
            .scaleEffect(isHovering ? 1.01 : 1)
            .onHover { hovering in
                isHovering = hovering
            }
            .onChange(of: context.date) {
                guard isAnimating && isVisible && thumbnails.count > 1 else { return }
                withAnimation(.easeInOut(duration: 0.1)) {
                    currentThumbnailIndex = (currentThumbnailIndex + 1) % thumbnails.count
                }
            }
            .onAppear {
                isVisible = true
                isAnimating = !isWaste
                loadThumbnails()
            }
            .onDisappear {
                isVisible = false
                isAnimating = false
            }
            .onChange(of: clip.id) { _, _ in
                loadThumbnails()
            }
            .onChange(of: size) { _, _ in
                loadThumbnails()
            }
        }
    }

    private var shortSourceName: String {
        clip.sourceFileURL.deletingPathExtension().lastPathComponent.prefix(8).uppercased()
    }

    private var wasteLabel: String {
        switch clip.wasteType {
        case .blackout: return "Blackout"
        case .dark: return "Dark"
        case .solid: return "Solid"
        case .blurry: return "Blurry"
        case .none: return ""
        }
    }

    @ViewBuilder
    private func statusBadge(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.framwiseMono(10))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.88))
        )
    }

    private func loadThumbnails() {
        loadTask?.cancel()
        isLoading = true
        thumbnails = []
        currentThumbnailIndex = 0

        loadTask = Task {
            do {
                let images = try await thumbnailGenerator.generateThumbnails(
                    for: clip,
                    count: 5,
                    targetSize: size
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.thumbnails = images
                    self.isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Helpers

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Corner Set

struct CornerSet: OptionSet {
    let rawValue: Int

    static let topLeft = CornerSet(rawValue: 1 << 0)
    static let topRight = CornerSet(rawValue: 1 << 1)
    static let bottomLeft = CornerSet(rawValue: 1 << 2)
    static let bottomRight = CornerSet(rawValue: 1 << 3)
    static let all: CornerSet = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

// MARK: - Rounded Corner Shape

struct RoundedCorners: Shape {
    var radius: CGFloat = .infinity
    var corners: CornerSet = .all

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Handle empty corners
        if corners.isEmpty {
            return Path(rect)
        }

        // Start from top-left
        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomLeft = corners.contains(.bottomLeft)
        let bottomRight = corners.contains(.bottomRight)

        // Build path
        if topLeft {
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        // Top edge
        if topRight {
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        // Right edge
        if bottomRight {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        // Bottom edge
        if bottomLeft {
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        // Left edge
        if topLeft {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: CornerSet) -> some View {
        clipShape(RoundedCorners(radius: radius, corners: corners))
    }
}

// MARK: - Preview

#Preview {
    let clip = VideoClip(
        sourceFileURL: URL(fileURLWithPath: "/path/to/video.mp4"),
        timecodeStart: CMTime(seconds: 10, preferredTimescale: 600),
        timecodeEnd: CMTime(seconds: 25, preferredTimescale: 600)
    )

    return ClipCellView(
        clip: clip,
        size: CGSize(width: 220, height: 150),
        isSelected: false,
        thumbnailGenerator: ThumbnailGenerator()
    )
}
