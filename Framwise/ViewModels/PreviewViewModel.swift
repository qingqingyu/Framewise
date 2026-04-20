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
    @Published var error: Error?
    @Published var playbackRate: Float = 2.0

    static let availableRates: [Float] = [1.0, 1.5, 2.0, 3.0, 4.0]

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    /// Load a clip for preview
    func loadClip(_ clip: VideoClip) {
        // Clean up previous player
        cleanupPlayer()
        error = nil

        currentClip = clip
        let asset = AVAsset(url: clip.sourceFileURL)
        let playerItem = AVPlayerItem(asset: asset)

        let newPlayer = AVPlayer(playerItem: playerItem)
        self.player = newPlayer

        // Set playback range
        let startTime = clip.timecodeStart
        let endTime = clip.timecodeEnd

        // Seek to start, then begin playback once ready
        newPlayer.seek(to: startTime, toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600)) { [weak self, weak newPlayer] _ in
            guard let self, let newPlayer else { return }
            self.playIfCurrent(newPlayer)
        }

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

            // Already on main queue — no Task needed
            self.currentTime = currentSeconds - startSeconds

            // Stop cleanly at the end of the clip and reset to the start frame.
            if self.isPlaying && currentSeconds >= endSeconds {
                player.pause()
                self.isPlaying = false
                player.seek(to: clipStartTime, toleranceBefore: .zero, toleranceAfter: .zero)
                self.currentTime = 0
            }
        }

        // Observe player item status (ready or failed)
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.duration = CMTimeGetSeconds(clip.timecodeEnd) - CMTimeGetSeconds(clip.timecodeStart)
                case .failed:
                    self?.error = playerItem.error ?? NSError(
                        domain: AVFoundationErrorDomain,
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to load video. The file may have been moved or deleted."]
                    )
                    self?.cleanupPlayer()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    /// Start playback at the configured rate
    func play() {
        guard let player = player else { return }
        if let clip = currentClip, duration > 0, currentTime >= max(duration - 0.05, 0) {
            currentTime = 0
            player.seek(to: clip.timecodeStart, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.rate = playbackRate
        isPlaying = true
    }

    func cyclePlaybackRate() {
        guard let idx = Self.availableRates.firstIndex(of: playbackRate) else {
            playbackRate = 2.0
            return
        }
        playbackRate = Self.availableRates[(idx + 1) % Self.availableRates.count]
        if isPlaying {
            player?.rate = playbackRate
        }
    }

    func playIfCurrent(_ candidatePlayer: AVPlayer) {
        guard let player, player === candidatePlayer else { return }
        play()
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
        player.seek(to: targetTime, toleranceBefore: CMTime(seconds: 0.1, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600))
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
