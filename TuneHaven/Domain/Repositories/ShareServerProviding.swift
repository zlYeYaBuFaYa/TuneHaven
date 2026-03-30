import Foundation

// MARK: - 分享服务器协议

@MainActor
protocol ShareServerProviding: AnyObject {
    var isRunning: Bool { get }
    var serverAddress: String? { get }
    var qrCodeContent: String? { get }
    var connectedDevice: String? { get }

    var dataSource: ShareDataSource? { get set }

    func start() async throws
    func stop()
}

// MARK: - 分享数据源协议

@MainActor
protocol ShareDataSource: AnyObject {
    func sessionInfo() -> ShareSessionInfo
    func songSummaries() -> [ShareSongSummary]
    func playlistSummaries() -> [SharePlaylistSummary]
    func audioFileURL(at index: Int) -> URL?
    func coverFileURL(at index: Int) -> URL?
    func lyricsFileURL(at index: Int) -> URL?
    func playlistSongs(at index: Int) -> [ShareSongSummary]
    func songExportData(at index: Int) -> SongExportData?
}

// MARK: - 分享客户端协议

protocol ShareClientProviding: AnyObject {
    func connect(to qrContent: String) async throws -> ShareSessionInfo
    func fetchSongList() async throws -> [ShareSongSummary]
    func fetchPlaylistList() async throws -> [SharePlaylistSummary]
    func fetchPlaylistSongs(at index: Int) async throws -> [ShareSongSummary]
    func fetchSongMeta(at index: Int) async throws -> SongExportData
    func downloadAudio(at index: Int, to dir: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws -> URL
    func downloadCover(at index: Int, to dir: URL) async throws -> URL?
    func downloadLyrics(at index: Int, to dir: URL) async throws -> URL?
    func disconnect()
}
