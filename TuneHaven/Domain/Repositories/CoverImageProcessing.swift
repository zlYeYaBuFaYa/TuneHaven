import Foundation

@MainActor
protocol CoverImageProcessing: AnyObject {
    func processSongCover(data: Data, songId: UUID) throws -> String?
    func processPlaylistCover(imageData: Data, playlistId: UUID) throws -> String
    func generatePlaylistGridCover(coverPaths: [String?], playlistId: UUID) throws -> String
}
