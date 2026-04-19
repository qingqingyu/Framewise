//
//  ClipPreviewView.swift
//  Framwise
//
//  Video preview panel with playback controls
//

import SwiftUI
import AVFoundation
import AVKit

struct ClipPreviewView: View {
    @ObservedObject var viewModel: PreviewViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            if let clip = viewModel.currentClip {
                videoPlayerView
                controlsView(clip: clip)
                clipInfoView(clip: clip)
            } else {
                emptyStateView
            }
        }
        .padding(16)
        .background(FramwiseTheme.appGradient)
    }

    private var videoPlayerView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(FramwiseTheme.line.opacity(0.85), lineWidth: 1)
                )

            if let player = viewModel.player {
                VideoPlayerView(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                FramwiseLoadingIndicator(tint: FramwiseTheme.warm, diameter: 26)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
    }

    private func controlsView(clip: VideoClip) -> some View {
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
                .help("Play/Pause (Space)")

                Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                    .font(.framwiseMono(11))
                    .foregroundStyle(FramwiseTheme.textMuted)

                Spacer()

                Button(action: { viewModel.seek(to: 0) }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(FramwiseGhostButtonStyle())
                .help("Restart clip")
            }

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
                            let targetTime = progress * viewModel.duration
                            viewModel.seek(to: targetTime)
                        }
                )
            }
            .frame(height: 18)
        }
        .padding(16)
        .framwisePanel(background: FramwiseTheme.surface, radius: 20)
    }

    private func clipInfoView(clip: VideoClip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLIP INFO")
                .font(.framwiseMono(10))
                .foregroundStyle(FramwiseTheme.warm)

            Text(clip.sourceFileName)
                .font(.framwiseDisplay(20, weight: .semibold))
                .foregroundStyle(FramwiseTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                FramwiseMetricBadge(title: "IN", value: clip.timecodeStartString, color: FramwiseTheme.textPrimary)
                FramwiseMetricBadge(title: "OUT", value: clip.timecodeEndString, color: FramwiseTheme.textPrimary)
                FramwiseMetricBadge(title: "DURATION", value: clip.durationString, color: FramwiseTheme.textPrimary)
            }

            if appState.selectedClipIDs.contains(clip.id) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FramwiseTheme.accent)
                    Text("Selected")
                        .font(.framwiseUI(12, weight: .medium))
                        .foregroundStyle(FramwiseTheme.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(FramwiseTheme.accentSoft)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(FramwiseTheme.accent.opacity(0.28), lineWidth: 1)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .framwisePanel(background: FramwiseTheme.surface, radius: 20)
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(FramwiseTheme.textMuted.opacity(0.8))

            Text("No Clip Selected")
                .font(.framwiseDisplay(24, weight: .semibold))
                .foregroundStyle(FramwiseTheme.textPrimary)

            Text("Select a clip to preview")
                .font(.framwiseUI(13))
                .foregroundStyle(FramwiseTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .framwisePanel(background: FramwiseTheme.surface, radius: 22)
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Video Player View (NSViewRepresentable)

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = false
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

// MARK: - Preview

#Preview {
    let appState = AppState()
    let previewViewModel = PreviewViewModel()

    let clip = VideoClip(
        sourceFileURL: URL(fileURLWithPath: "/path/to/video.mp4"),
        timecodeStart: CMTime(seconds: 10, preferredTimescale: 600),
        timecodeEnd: CMTime(seconds: 25, preferredTimescale: 600)
    )

    previewViewModel.loadClip(clip)

    return ClipPreviewView(viewModel: previewViewModel)
        .environmentObject(appState)
        .frame(width: 320, height: 400)
}
