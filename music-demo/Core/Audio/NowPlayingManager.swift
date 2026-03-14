import MediaPlayer
import UIKit

final class NowPlayingManager {
    static let shared = NowPlayingManager()
    private init() {}

    func update(song: Song, currentTime: TimeInterval, duration: TimeInterval, speed: Float, cover: UIImage?) {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = song.title
        info[MPMediaItemPropertyArtist] = song.artist
        info[MPMediaItemPropertyAlbumTitle] = song.album
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = speed
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Float(1.0)
        if let cover {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: cover.size) { _ in cover }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func setupRemoteCommands(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { _ in onPlay(); return .success }
        center.pauseCommand.addTarget { _ in onPause(); return .success }
        center.togglePlayPauseCommand.addTarget { _ in
            if AudioEngine.shared.isPlaying { onPause() } else { onPlay() }
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
