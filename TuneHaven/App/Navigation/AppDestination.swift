import Foundation

enum AppDestination: Hashable {
    case artistDetail(name: String)
    case albumDetail(album: String, artist: String)
    case playlistDetail(id: UUID)
    case songList(title: String, context: SongListContext)
    case importFiles
    case settings
    case songInfoEdit(songId: UUID)
}

enum SongListContext: Hashable {
    case allSongs
    case favorites
    case recentlyPlayed
    case artist(name: String)
    case album(name: String, artist: String)
    case playlist(id: UUID)
}

enum SheetDestination: Identifiable {
    case createPlaylist
    case addToPlaylist(songIds: [UUID])
    case editPlaylist(id: UUID)
    case playlistCoverPicker(id: UUID)
    case setSleepTimer
    case playbackSpeedPicker
    case importFromFiles
    case batchAddSongs(playlistId: UUID)
    case paywall(feature: PremiumFeature? = nil)

    var id: String {
        switch self {
        case .createPlaylist: return "createPlaylist"
        case .addToPlaylist(let ids): return "addToPlaylist_\(ids.count)_\(ids.prefix(3).map(\.uuidString).joined(separator: ","))_\(ids.hashValue)"
        case .editPlaylist(let id): return "editPlaylist_\(id)"
        case .playlistCoverPicker(let id): return "coverPicker_\(id)"
        case .setSleepTimer: return "sleepTimer"
        case .playbackSpeedPicker: return "speedPicker"
        case .importFromFiles: return "importFromFiles"
        case .batchAddSongs(let id): return "batchAddSongs_\(id)"
        case .paywall(let feature): return "paywall_\(feature?.rawValue ?? "general")"
        }
    }
}
