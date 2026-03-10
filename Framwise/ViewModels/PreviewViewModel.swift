//
//  PreviewViewModel.swift
//  Framwise
//
//  Manages video preview playback
//

import Foundation
import AVFoundation
import Combine

@MainActor
class PreviewViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentClip: VideoClip?

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    /// Load a clip for preview
    func loadClip(_ clip: VideoClip) {
        // Clean up previous player
        cleanupPlayer()

        currentClip = clip
        let asset = AVAsset(url: clip.sourceFileURL)
        let playerItem = AVPlayerItem(asset: asset)

        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer

        // Set playback range
        let startTime = clip.timecodeStart
        let endTime = clip.timecodeEnd

        // Seek to start
        newPlayer.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)

        duration = CMTimeGetSeconds(endTime) - CMTimeGetSeconds(startTime)

        // Add time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        let clipStartTime = clip.timecodeStart
        let clipEndTime = clip.timecodeEnd
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak newPlayer] time in
            guard let self = self, let player = newPlayer else { return }
            let currentSeconds = CMTimeGetSeconds(time)
            let startSeconds = CMTimeGetSeconds(clipStartTime)
            let endSeconds = CMTimeGetSeconds(clipEndTime)

            Task { @MainActor in
                self.currentTime = currentSeconds - startSeconds

                // Stop at end and loop back to start
                if currentSeconds >= endSeconds {
                    self.pause()
                    player.seek(to: clipStartTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    self.currentTime = 0
                }
            }
        }

        // Observe when item is ready
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                if status == .readyToPlay {
                    self?.duration = CMTimeGetSeconds(clip.timecodeEnd) - CMTimeGetSeconds(clip.timecodeStart)
                }
            }
            .store(in: &cancellables)
    }

    /// Start playback
    func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
    }

    /// Pause playback
    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Seek to a specific time within the clip
    func seek(to time: Double) {
        guard let player = player, let clip = currentClip else { return }
        let targetTime = CMTimeAdd(clip.timecodeStart, CMTime(seconds: time, preferredTimescale: 600))
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    /// Clean up player resources
    func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        cancellables.removeAll()
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}
