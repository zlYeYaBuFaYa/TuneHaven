import Foundation

protocol CoverImageProcessing: AnyObject {
    func processSongCover(data: Data, songId: UUID) async throws -> String?
    func processPlaylistCover(imageData: Data, playlistId: UUID) async throws -> String
    func generatePlaylistGridCover(coverPaths: [String?], playlistId: UUID) async throws -> String
}
