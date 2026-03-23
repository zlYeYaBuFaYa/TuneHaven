import Foundation

protocol AudioMetadataParsing: AnyObject {
    func parse(url: URL) async -> ParsedMetadata
}
