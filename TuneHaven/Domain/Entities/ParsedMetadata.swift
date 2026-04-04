import Foundation

struct ParsedMetadata: Sendable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let format: String
    let sampleRate: Int?
    let bitRate: Int?
    let channels: Int?
    let trackNumber: Int?
    let year: Int?
    let genre: String?
    let encoder: String?
    let coverImageData: Data?
    let isIncomplete: Bool
}
