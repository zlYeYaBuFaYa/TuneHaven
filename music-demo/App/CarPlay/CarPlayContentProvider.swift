import CarPlay
import UIKit
import Combine

@MainActor
final class CarPlayContentProvider: NSObject {

    weak var interfaceController: CPInterfaceController?

    private let playbackService = PlaybackService.shared
    private let libraryService = MusicLibraryService()
    private let playlistService = PlaylistService()
    private let songRepo = CoreDataSongRepository()
    private let imageCache = ImageCacheManager.shared
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        observePlaybackChanges()
    }

    // MARK: - Now Playing Tab

    func makeNowPlayingTab() -> CPTemplate {
        let template = CPNowPlayingTemplate.shared
        template.updateNowPlayingButtons(makeNowPlayingButtons())
        let wrapper = wrapInList(
            title: "正在播放",
            systemImage: "music.note",
            template: template
        )
        return wrapper
    }

    // MARK: - Songs Tab

    func makeSongsTab() -> CPListTemplate {
        let template = CPListTemplate(title: "歌曲", sections: [])
        template.tabTitle = "歌曲"
        template.tabImage = UIImage(systemName: "music.note.list")
        template.emptyViewTitleVariants = ["暂无歌曲"]
        template.emptyViewSubtitleVariants = ["请先在 iPhone 上导入音乐"]
        loadSongs(into: template)
        return template
    }

    // MARK: - Albums Tab

    func makeAlbumsTab() -> CPListTemplate {
        let template = CPListTemplate(title: "专辑", sections: [])
        template.tabTitle = "专辑"
        template.tabImage = UIImage(systemName: "square.stack")
        template.emptyViewTitleVariants = ["暂无专辑"]
        loadAlbums(into: template)
        return template
    }

    // MARK: - Playlists Tab

    func makePlaylistsTab() -> CPListTemplate {
        let template = CPListTemplate(title: "歌单", sections: [])
        template.tabTitle = "歌单"
        template.tabImage = UIImage(systemName: "list.bullet")
        template.emptyViewTitleVariants = ["暂无歌单"]
        loadPlaylists(into: template)
        return template
    }

    // MARK: - Data Loading

    private func loadSongs(into template: CPListTemplate) {
        Task {
            let songs = await songRepo.fetchAll(sortBy: .title, ascending: true)
            let items = songs.map { song in
                makeSongItem(song: song, context: .allSongs(sortBy: .title))
            }
            let section = CPListSection(items: items)
            template.updateSections([section])
        }
    }

    private func loadAlbums(into template: CPListTemplate) {
        Task {
            let albums = await libraryService.fetchSongsByAlbum()
            let items: [CPListItem] = albums.map { album in
                let item = CPListItem(
                    text: album.name,
                    detailText: "\(album.artist) · \(album.songCount)首"
                )
                if let coverPath = album.coverImagePath,
                   let image = imageCache.image(forKey: coverPath) {
                    item.setImage(image)
                }
                item.handler = { [weak self] _, completion in
                    self?.showAlbumDetail(album: album)
                    completion()
                }
                return item
            }
            let section = CPListSection(items: items)
            template.updateSections([section])
        }
    }

    private func loadPlaylists(into template: CPListTemplate) {
        Task {
            await playlistService.loadPlaylists()
            let playlists = playlistService.playlists

            var items: [CPListItem] = []

            let favItem = CPListItem(
                text: "我喜欢",
                detailText: nil
            )
            favItem.setImage(UIImage(systemName: "heart.fill"))
            favItem.handler = { [weak self] _, completion in
                self?.showFavorites()
                completion()
            }
            items.append(favItem)

            for playlist in playlists where !playlist.isSystem {
                let item = CPListItem(
                    text: playlist.name,
                    detailText: "\(playlist.songCount)首"
                )
                item.setImage(UIImage(systemName: "music.note.list"))
                item.handler = { [weak self] _, completion in
                    self?.showPlaylistDetail(playlist: playlist)
                    completion()
                }
                items.append(item)
            }

            let section = CPListSection(items: items)
            template.updateSections([section])
        }
    }

    // MARK: - Detail Views

    private func showAlbumDetail(album: AlbumGroup) {
        Task {
            let detail = await libraryService.fetchAlbumDetail(album: album.name, artist: album.artist)
            let items = detail.songs.map { song in
                makeSongItem(song: song, context: .album(name: album.name, artist: album.artist))
            }
            let section = CPListSection(items: items)
            let template = CPListTemplate(title: album.name, sections: [section])
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showPlaylistDetail(playlist: Playlist) {
        Task {
            guard let detail = await playlistService.fetchDetail(playlistId: playlist.id) else { return }
            let items = detail.songs.map { song in
                makeSongItem(song: song, context: .playlist(id: playlist.id))
            }
            let section = CPListSection(items: items)
            let template = CPListTemplate(title: playlist.name, sections: [section])
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func showFavorites() {
        Task {
            let songs = await playlistService.fetchFavorites()
            let items = songs.map { song in
                makeSongItem(song: song, context: .allSongs(sortBy: .title))
            }
            let section = CPListSection(items: items)
            let template = CPListTemplate(title: "我喜欢", sections: [section])
            template.emptyViewTitleVariants = ["暂无收藏"]
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    // MARK: - Song Item

    private func makeSongItem(song: Song, context: PlayContext) -> CPListItem {
        let item = CPListItem(
            text: song.title,
            detailText: "\(song.artist) - \(song.album)"
        )
        item.isExplicitContent = false
        item.playbackProgress = 0

        if let coverPath = song.coverImagePath,
           let image = imageCache.image(forKey: coverPath) {
            item.setImage(image)
        } else {
            item.setImage(UIImage(systemName: "music.note"))
        }

        if song.id == playbackService.currentSong?.id {
            item.isPlaying = playbackService.isPlaying
        }

        item.handler = { [weak self] _, completion in
            guard let self else { completion(); return }
            Task { @MainActor in
                await self.playbackService.play(song: song, in: context)
                completion()
            }
        }
        return item
    }

    // MARK: - Now Playing Buttons

    private func makeNowPlayingButtons() -> [CPNowPlayingButton] {
        let shuffleButton = CPNowPlayingShuffleButton { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.playbackService.cyclePlayMode()
            }
        }

        let repeatButton = CPNowPlayingRepeatButton { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.playbackService.cyclePlayMode()
            }
        }

        return [shuffleButton, repeatButton]
    }

    // MARK: - Observe Playback

    private func observePlaybackChanges() {
        playbackService.$currentSong
            .combineLatest(playbackService.$isPlaying)
            .sink { [weak self] _, _ in
                self?.updateNowPlayingTemplate()
            }
            .store(in: &cancellables)
    }

    private func updateNowPlayingTemplate() {
        let template = CPNowPlayingTemplate.shared
        template.updateNowPlayingButtons(makeNowPlayingButtons())
        template.isUpNextButtonEnabled = true
        template.upNextTitle = "播放队列"
    }

    // MARK: - Helpers

    private func wrapInList(title: String, systemImage: String, template: CPNowPlayingTemplate) -> CPTemplate {
        template.tabTitle = title
        template.tabImage = UIImage(systemName: systemImage)
        return template
    }
}

// MARK: - CPTabBarTemplateDelegate

extension CarPlayContentProvider: CPTabBarTemplateDelegate {
    nonisolated func tabBarTemplate(
        _ tabBarTemplate: CPTabBarTemplate,
        didSelect selectedTemplate: CPTemplate
    ) {
        print("[CarPlay] Tab selected: \(selectedTemplate)")
    }
}
