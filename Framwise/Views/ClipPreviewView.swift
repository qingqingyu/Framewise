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
        VStack(spacing: 0) {
            if let clip = viewModel.currentClip {
                // Video player
                videoPlayerView

                Divider()

                // Controls
                controlsView(clip: clip)

                Divider()

                // Clip info
                clipInfoView(clip: clip)
            } else {
                emptyStateView
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Video Player View

    private var videoPlayerView: some View {
        ZStack {
            if let player = viewModel.player {
                VideoPlayerView(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    )
            }
        }
    }

    // MARK: - Controls View

    private func controlsView(clip: VideoClip) -> some View {
        VStack(spacing: 8) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)

                    // Progress
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: max(0, min(geometry.size.width * (viewModel.currentTime / max(viewModel.duration, 1)), geometry.size.width)), height: 4)
                        .cornerRadius(2)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            viewModel.currentTime = progress * viewModel.duration
                        }
                        .onEnded { value in
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            let targetTime = progress * viewModel.duration
                            viewModel.seek(to: targetTime)
                        }
                )
            }
            .frame(height: 12)

            // Controls row
            HStack(spacing: 16) {
                // Play/Pause button
                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Play/Pause (Space)")

                // Time display
                Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                // Restart button
                Button(action: { viewModel.seek(to: 0) }) {
                    Image(systemName: "backward.end.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .help("Restart clip")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Clip Info View

    private func clipInfoView(clip: VideoClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // File name
            Text(clip.sourceFileName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            // Timecode range
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(clip.timecodeStartString) - \(clip.timecodeEndString)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Duration
            HStack {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Duration: \(clip.durationString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Selection status
            if appState.selectedClipIDs.contains(clip.id) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("Selected")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Clip Selected")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Select a clip to preview")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helpers

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
