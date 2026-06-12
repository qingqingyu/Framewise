//
//  ClipPreviewModal.swift
//  Framwise
//
//  Modal clip preview surface
//

import SwiftUI

// MARK: - Clip Preview Modal

struct ClipPreviewModal: View {
    @EnvironmentObject var appState: AppState
    let clip: VideoClip
    @Binding var isPresented: Bool

    @StateObject private var viewModel = PreviewViewModel()

    private var liveClip: VideoClip {
        appState.importSession?.allClips.first(where: { $0.id == clip.id }) ?? clip
    }

    private var isClipMissingFromSession: Bool {
        guard let session = appState.importSession else { return false }
        return !session.allClips.contains { $0.id == clip.id }
    }

    private var clipTags: [ClipTag] {
        (appState.importSession?.tags ?? []).filter { liveClip.tagIDs.contains($0.id) }
    }

    private var isSelected: Bool {
        appState.selectedClipIDs.contains(clip.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PREVIEW MONITOR")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.warm)
                    Text(clip.sourceFileName)
                        .font(.framwiseDisplay(24, weight: .semibold))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                        .lineLimit(1)
                    Text("\(clip.timecodeStartString) - \(clip.timecodeEndString)")
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }
                Spacer()
                Button(action: {
                    viewModel.cleanupPlayer()
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(FramwiseGhostButtonStyle(
                    fill: FramwiseTheme.surfaceRaised,
                    border: FramwiseTheme.line.opacity(0.8),
                    foreground: FramwiseTheme.textMuted
                ))
                .keyboardShortcut(.escape, modifiers: [])
            }

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(FramwiseTheme.line.opacity(0.8), lineWidth: 1)
                    )

                if isClipMissingFromSession {
                    FramwiseStatePanel(
                        state: .empty,
                        title: "Clip no longer in session",
                        message: "This preview item was removed from the current workspace.",
                        systemImage: "film.badge.exclamationmark",
                        compact: true
                    )
                    .padding(28)
                } else if let error = viewModel.error {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(FramwiseTheme.warning)
                        Text(error.localizedDescription)
                            .font(.framwiseUI(13))
                            .foregroundStyle(FramwiseTheme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else if let player = viewModel.player {
                    VideoPlayerView(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    FramwiseLoadingIndicator(tint: FramwiseTheme.warm, diameter: 28)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: { viewModel.togglePlayPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: FramwiseTheme.accentSoft,
                        border: FramwiseTheme.accent.opacity(0.35),
                        foreground: FramwiseTheme.textPrimary
                    ))

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(FramwiseTheme.surfaceRaised)
                                .frame(height: 6)

                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [FramwiseTheme.accent, FramwiseTheme.warm.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, min(geometry.size.width * (viewModel.currentTime / max(viewModel.duration, 1)), geometry.size.width)), height: 6)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    let targetTime = progress * viewModel.duration
                                    viewModel.currentTime = targetTime
                                    viewModel.seek(to: targetTime)
                                }
                                .onEnded { value in
                                    let progress = max(0, min(1, value.location.x / geometry.size.width))
                                    viewModel.seek(to: progress * viewModel.duration)
                                }
                        )
                    }
                    .frame(height: 20)

                    Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                        .font(.framwiseMono(11))
                        .foregroundStyle(FramwiseTheme.textMuted)
                        .frame(width: 110, alignment: .trailing)

                    Button(action: { viewModel.seek(to: 0) }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(FramwiseGhostButtonStyle())
                }

                HStack(spacing: 12) {
                    FramwiseMetricBadge(title: "IN", value: clip.timecodeStartString, color: FramwiseTheme.textPrimary)
                    FramwiseMetricBadge(title: "OUT", value: clip.timecodeEndString, color: FramwiseTheme.textPrimary)
                    FramwiseMetricBadge(title: "DURATION", value: clip.durationString, color: FramwiseTheme.textPrimary)
                }

                HStack(spacing: 10) {
                    Button(action: toggleSelection) {
                        Label(
                            isSelected ? "Selected" : "Add to Selection",
                            systemImage: isSelected ? "checkmark.circle.fill" : "plus.circle"
                        )
                    }
                    .buttonStyle(FramwiseGhostButtonStyle(
                        fill: isSelected ? FramwiseTheme.accentSoft : FramwiseTheme.surfaceRaised,
                        border: isSelected ? FramwiseTheme.accent.opacity(0.35) : FramwiseTheme.line.opacity(0.8),
                        foreground: isSelected ? FramwiseTheme.textPrimary : FramwiseTheme.textMuted
                    ))

                    if liveClip.effectiveWasteType != .none {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(FramwiseTheme.danger)
                                .frame(width: 8, height: 8)
                            Text(liveClip.effectiveWasteType.rawValue.uppercased())
                                .font(.framwiseMono(10))
                                .foregroundStyle(FramwiseTheme.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(FramwiseTheme.danger.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(FramwiseTheme.danger.opacity(0.28), lineWidth: 1)
                        )
                    }

                    Spacer()

                    Text("SPACE play/pause  ·  ESC close")
                        .font(.framwiseMono(10))
                        .foregroundStyle(FramwiseTheme.textMuted)
                }

                if !clipTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(clipTags) { tag in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(tag.color.systemColor)
                                        .frame(width: 8, height: 8)
                                    Text(tag.name)
                                        .lineLimit(1)
                                }
                                .font(.framwiseUI(12, weight: .medium))
                                .foregroundStyle(FramwiseTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(tag.color.systemColor.opacity(0.14))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(tag.color.systemColor.opacity(0.28), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
            .framwisePanel(background: FramwiseTheme.surface, radius: 20)
        }
        .padding(20)
        .frame(width: 760, height: 560)
        .background(FramwiseTheme.background)
        .focusable()
        .onKeyPress(.space) {
            viewModel.togglePlayPause()
            return .handled
        }
        .onAppear {
            if !isClipMissingFromSession {
                viewModel.loadClip(clip)
            }
        }
        .onDisappear {
            viewModel.cleanupPlayer()
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func toggleSelection() {
        if isSelected {
            appState.selectedClipIDs.remove(clip.id)
        } else {
            appState.selectedClipIDs.insert(clip.id)
        }
        appState.updatePreviewFromSelection()
    }
}
