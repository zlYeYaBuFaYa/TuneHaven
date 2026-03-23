import Foundation

extension LRCLibTrack {
    var durationText: String {
        DurationFormatter.format(duration)
    }
}
