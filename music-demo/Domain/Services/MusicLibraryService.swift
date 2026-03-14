import Foundation
import Combine

@MainActor
final class MusicLibraryService: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false

    private let songRepo: CoreDataSongRepository
    private var pendingUndoTokens: [UndoToken] = []
    private var undoTimers: [UUID: Timer] = [:]

    init(songRepo: CoreDataSongRepository = CoreDataSongRepository()) {
        self.songRepo = songRepo
    }

    func loadSongs(sortBy: SongSortOption = .title, ascending: Bool = true) async {
        isLoading = true
        songs = await songRepo.fetchAll(sortBy: sortBy, ascending: ascending)
        isLoading = false
    }

    func fetchSongsByArtist() async -> [ArtistGroup] {
        let all = await songRepo.fetchAll(sortBy: .artist, ascending: true)
        var groups: [String: (songCount: Int, albums: Set<String>)] = [:]
        for song in all {
            var g = groups[song.artist] ?? (0, [])
            g.songCount += 1
            g.albums.insert(song.album)
            groups[song.artist] = g
        }
        return groups.map { ArtistGroup(name: $0.key, songCount: $0.value.songCount, albumCount: $0.value.albums.count) }
                     .sorted { $0.name < $1.name }
    }

    func fetchSongsByAlbum() async -> [AlbumGroup] {
        let all = await songRepo.fetchAll(sortBy: .album, ascending: true)
        var groups: [String: (artist: String, year: Int?, count: Int, cover: String?)] = [:]
        for song in all {
            let key = "\(song.artist)/\(song.album)"
            var g = groups[key] ?? (song.artist, song.metadata.year, 0, song.coverImagePath)
            g.count += 1
            groups[key] = g
        }
        return groups.map { AlbumGroup(name: String($0.key.split(separator: "/").last ?? ""), artist: $0.value.artist, year: $0.value.year, songCount: $0.value.count, coverImagePath: $0.value.cover) }
                     .sorted { $0.name < $1.name }
    }

    func fetchArtistDetail(artist: String) async -> ArtistDetail {
        let all = await songRepo.fetchAll(sortBy: .album, ascending: true)
        let artistSongs = all.filter { $0.artist == artist }
        var albumMap: [String: [Song]] = [:]
        for song in artistSongs { albumMap[song.album, default: []].append(song) }
        let albums = albumMap.map { AlbumGroup(name: $0.key, artist: artist, year: $0.value.first?.metadata.year, songCount: $0.value.count, coverImagePath: $0.value.first?.coverImagePath) }.sorted { $0.name < $1.name }
        return ArtistDetail(name: artist, albums: albums, allSongs: artistSongs)
    }

    func fetchAlbumDetail(album: String, artist: String) async -> AlbumDetail {
        let all = await songRepo.fetchAll(sortBy: .title, ascending: true)
        let songs = all.filter { $0.album == album && $0.artist == artist }
                       .sorted { ($0.metadata.trackNumber ?? 999) < ($1.metadata.trackNumber ?? 999) }
        return AlbumDetail(name: album, artist: artist, year: songs.first?.metadata.year, songs: songs, coverImagePath: songs.first?.coverImagePath)
    }

    func softDelete(songIds: [UUID]) async throws -> UndoToken {
        let token = try await songRepo.softDelete(ids: songIds)
        pendingUndoTokens.append(token)
        await loadSongs()
        scheduleCommit(token: token)
        return token
    }

    func undoDelete(token: UndoToken) async throws {
        invalidateTimer(for: token)
        try await songRepo.undoDelete(token: token)
        pendingUndoTokens.removeAll { $0.songIds == token.songIds }
        await loadSongs()
    }

    func toggleFavorite(songId: UUID) async throws {
        try await songRepo.toggleFavorite(id: songId)
        await loadSongs()
    }

    func recordPlay(songId: UUID) async throws {
        try await songRepo.recordPlay(id: songId)
    }

    func fetchRecentlyPlayed(days: Int, page: Int, pageSize: Int = 50) async -> PagedResult<Song> {
        await songRepo.fetchRecentlyPlayed(days: days, page: page, pageSize: pageSize)
    }

    func cleanupOnLaunch() async {
        await songRepo.cleanupPendingDeletes()
    }

    private func scheduleCommit(token: UndoToken) {
        let id = token.songIds.first ?? UUID()
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await self?.songRepo.commitDelete(token: token)
                self?.pendingUndoTokens.removeAll { $0.songIds == token.songIds }
            }
        }
        undoTimers[id] = timer
    }

    private func invalidateTimer(for token: UndoToken) {
        if let id = token.songIds.first {
            undoTimers[id]?.invalidate()
            undoTimers.removeValue(forKey: id)
        }
    }
}
