import Foundation
@testable import TuneHaven

// MARK: - Song Factory（默认参数适用于多数单元测试；分组/搜索等有特殊字段需求的测试可保留文件内自定义工厂）

func makeSong(
    id: UUID = UUID(),
    title: String = "Test Song",
    artist: String = "Test Artist",
    album: String = "Test Album",
    duration: TimeInterval = 180,
    fileHash: String = UUID().uuidString,
    trackNumber: Int? = nil,
    year: Int? = 2024,
    coverImagePath: String? = nil
) -> Song {
    Song(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        fileHash: fileHash,
        fileRelativePath: "\(fileHash).mp3",
        coverImagePath: coverImagePath,
        lyricsPath: nil,
        lyricsSource: nil,
        metadata: Metadata(
            format: "mp3",
            sampleRate: 44100,
            bitRate: 320,
            channels: 2,
            encoder: nil,
            trackNumber: trackNumber,
            year: year,
            genre: nil
        ),
        importDate: Date(),
        fileSize: 1024 * 1024,
        playCount: 0,
        isFavorite: false,
        favoriteDate: nil,
        lastPlayedDate: nil
    )
}

func makeSongs(count: Int) -> [Song] {
    (0..<count).map { makeSong(title: "Song \($0)") }
}
