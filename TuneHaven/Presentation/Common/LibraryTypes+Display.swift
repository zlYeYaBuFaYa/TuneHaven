import Foundation

extension SongSortOption {
    var displayName: String {
        switch self {
        case .title: return "文件名"
        case .fileSize: return "文件大小"
        case .importDate: return "添加时间"
        case .artist: return "艺术家"
        case .album: return "专辑"
        case .duration: return "时长"
        }
    }
}

extension AudioFormat {
    var displayName: String {
        switch self {
        case .all: return "全部格式"
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .aac: return "AAC"
        case .alac: return "ALAC（无损）"
        case .wav: return "WAV"
        case .flac: return "FLAC（无损）"
        case .aiff: return "AIFF（无损）"
        case .caf: return "CAF"
        }
    }
}

extension LibraryTab {
    var displayName: String {
        switch self {
        case .all: return "全部"
        case .artist: return "艺术家"
        case .album: return "专辑"
        }
    }
}

extension PlayMode {
    var displayName: String {
        switch self {
        case .sequential: return "顺序播放"
        case .repeatOne: return "单曲循环"
        case .repeatAll: return "列表循环"
        case .shuffle: return "随机播放"
        }
    }

    var iconName: String {
        switch self {
        case .sequential: return "arrow.right"
        case .repeatOne: return "repeat.1"
        case .repeatAll: return "repeat"
        case .shuffle: return "shuffle"
        }
    }
}
