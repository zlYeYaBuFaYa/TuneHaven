import MediaPlayer
import UIKit

@MainActor
final class NowPlayingManager: NowPlayingManaging {
    static let shared = NowPlayingManager()
    private let imageCache = ImageCacheManager.shared
    private init() {}

    func update(song: Song, currentTime: TimeInterval, duration: TimeInterval, speed: Float, coverPath: String?) async {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist
        info[MPMediaItemPropertyAlbumTitle] = song.album
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = speed
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Float(1.0)
        if let coverPath, let coverData = await imageCache.imageDataAsync(forKey: coverPath),
           let cover = UIImage(data: coverData) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Lightweight update — only refreshes elapsed time without recreating the entire info dict.
    /// Called periodically from the time observer to keep iOS informed of playback progress.
    func updateElapsedTime(currentTime: TimeInterval, duration: TimeInterval, speed: Float) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = speed
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Call only once during app lifecycle. Uses `removeTarget(nil)` to clear all prior
    /// handlers before registering new ones, so repeated calls are safe but unnecessary.
    func setupRemoteCommands(
        onPlay: @escaping @Sendable () -> Void,
        onPause: @escaping @Sendable () -> Void,
        onTogglePlayPause: @escaping @Sendable () -> Void,
        onNext: @escaping @Sendable () -> Void,
        onPrevious: @escaping @Sendable () -> Void,
        onSeek: @escaping @Sendable (TimeInterval) -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true

        center.playCommand.addTarget { _ in onPlay(); return .success }
        center.pauseCommand.addTarget { _ in onPause(); return .success }
        center.togglePlayPauseCommand.addTarget { _ in
            onTogglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { _ in onNext(); return .success }
        center.previousTrackCommand.addTarget { _ in onPrevious(); return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            onSeek(e.positionTime)
            return .success
        }
    }
}
