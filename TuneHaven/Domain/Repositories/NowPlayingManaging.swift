import Foundation

@MainActor
protocol NowPlayingManaging: AnyObject {
    func update(song: Song, currentTime: TimeInterval, duration: TimeInterval, speed: Float, coverPath: String?) async
    func updateElapsedTime(currentTime: TimeInterval, duration: TimeInterval, speed: Float)
    func clear()
    func setupRemoteCommands(
        onPlay: @escaping @Sendable () -> Void,
        onPause: @escaping @Sendable () -> Void,
        onTogglePlayPause: @escaping @Sendable () -> Void,
        onNext: @escaping @Sendable () -> Void,
        onPrevious: @escaping @Sendable () -> Void,
        onSeek: @escaping @Sendable (TimeInterval) -> Void
    )
}
