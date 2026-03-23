import Foundation
import Combine

enum PlaybackState: Equatable {
    case idle, loading, playing, paused
    case error(Error)

    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.playing, .playing), (.paused, .paused):
            return true
        case (.error(let l), .error(let r)):
            return String(describing: l) == String(describing: r)
        default:
            return false
        }
    }
}

@MainActor
protocol AudioEngineProtocol: AnyObject {
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var state: PlaybackState { get }
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }
    var playbackEndedPublisher: AnyPublisher<Void, Never> { get }
    var timeUpdatePublisher: AnyPublisher<(currentTime: TimeInterval, duration: TimeInterval), Never> { get }

    func load(url: URL) async
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func skip(by seconds: TimeInterval)
    func setSpeed(_ speed: Float)
    func togglePlayPause()
}
