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

    @State private var thumbnails: [CGImage] = []
    @State private var currentThumbnailIndex = 0
    @State private var isHovering = false
    @State private var isLoading = true
    @State private var isAnimating = false
    @State private var isVisible = false
    @State private var loadTask: Task<Void, Never>?

    private var isWaste: Bool { clip.wasteType != .none }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
            ZStack(alignment: .bottomLeading) {
                // Thumbnail
                Group {
                    if let currentThumbnail = thumbnails[safe: currentThumbnailIndex] {
                        Image(nsImage: currentThumbnail.nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if isLoading {
                        // Loading placeholder
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.5)
                            )
                    } else {
                        // Fallback
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .overlay(
                                Image(systemName: "film")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                            )
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .cornerRadius(8)

                // Selection indicator
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .frame(width: size.width, height: size.height)

                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                                .padding(6)
                                .background(Color.white.opacity(0.8))
                                .clipShape(Circle())
                                .padding(6)
                        }
                        Spacer()
                    }
                }

                // Hover effect
                if isHovering && !isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: size.width, height: size.height)
                }

                // Waste overlay
                if isWaste {
                    // Red tint overlay
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.4))
                        .frame(width: size.width, height: size.height)

                    // Waste badge
                    VStack {
                        HStack {
                            HStack(spacing: 3) {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                Text(wasteLabel)
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(4)
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Info overlay
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            // Tag dots (sorted by tag order in session, not UUID)
                            if !clip.tagIDs.isEmpty {
                                HStack(spacing: 3) {
                                    ForEach(Array(tags.filter { clip.tagIDs.contains($0.id) }.prefix(4))) { tag in
                                        Circle()
                                            .fill(tag.color.systemColor)
                                            .frame(width: 6, height: 6)
                                    }
                                    if clip.tagIDs.count > 4 {
                                        Text("+\(clip.tagIDs.count - 4)")
                                            .font(.system(size: 8))
                                            .foregroundColor(.white)
                                    }
                                }
                            }

                            Text(clip.durationString)
                                .font(.caption)
                                .fontWeight(.semibold)

                            Text(clip.timecodeStartString)
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.white)

                        Spacer()

                        // Source indicator
                        Image(systemName: "video.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(8)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.7), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
                }
                .frame(width: size.width, height: size.height)
            }
            .onHover { hovering in
                isHovering = hovering
            }
            .onChange(of: context.date) {
                // Advance thumbnail animation on each timeline tick
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

    private var wasteLabel: String {
        switch clip.wasteType {
        case .blackout: return "Blackout"
        case .dark: return "Dark"
        case .solid: return "Solid"
        case .none: return ""
        }
    }

    private func loadThumbnails() {
        // Cancel any in-flight load
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
