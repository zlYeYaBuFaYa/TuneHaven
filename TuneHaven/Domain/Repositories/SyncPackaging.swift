import Foundation

/// 同步打包/解包协议 — Domain 层定义，Core 层实现
protocol SyncPackaging: AnyObject {
    func export(
        songs: [Song],
        playlists: [PlaylistDetail],
        includeAudioFiles: Bool,
        groupNames: [UUID: String],
        progressHandler: @escaping (SyncProgress) -> Void
    ) async throws -> URL

    func unpack(
        fileURL: URL,
        progressHandler: @escaping (SyncProgress) -> Void
    ) async throws -> (manifest: TuneHavenManifest, extractedDir: URL)

    func estimateExportSize(
        songs: [Song],
        playlists: [PlaylistDetail],
        includeAudioFiles: Bool
    ) -> Int64
}
