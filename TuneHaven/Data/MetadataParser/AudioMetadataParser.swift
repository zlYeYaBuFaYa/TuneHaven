import AVFoundation
import UIKit
import Foundation

struct ParsedMetadata {
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
    let coverImage: UIImage?
    let isIncomplete: Bool
}

final class AudioMetadataParser {
    static let shared = AudioMetadataParser()
    private init() {}

    func parse(url: URL) async -> ParsedMetadata {
        let asset = AVURLAsset(url: url)
        let fileName = (url.lastPathComponent as NSString).deletingPathExtension
        let ext = url.pathExtension.lowercased()

        var title = fileName
        var artist = "未知艺术家"
        var album = "未知专辑"
        var duration: TimeInterval = 0
        var trackNumber: Int?
        var year: Int?
        var genre: String?
        var coverImage: UIImage?
        var sampleRate: Int?
        var bitRate: Int?
        var channels: Int?
        var encoder: String?
        var isIncomplete = false

        do {
            let cmDuration = try await asset.load(.duration)
            duration = cmDuration.seconds.isNaN ? 0 : cmDuration.seconds

            let metadataItems = try await asset.load(.commonMetadata)
            for item in metadataItems {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case .commonKeyArtist:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue), let img = UIImage(data: data) {
                        coverImage = img
                    }
                default: break
                }
            }

            let allMetadata = try await asset.load(.metadata)
            for item in allMetadata {
                if let id3Key = item.identifier {
                    switch id3Key {
                    case .id3MetadataTrackNumber:
                        if let v = try? await item.load(.stringValue) {
                            trackNumber = Int(v.components(separatedBy: "/").first ?? v)
                        }
                    case .id3MetadataYear, .id3MetadataRecordingTime:
                        if let v = try? await item.load(.stringValue) {
                            year = Int(v.prefix(4))
                        }
                    case .id3MetadataContentType:
                        if let v = try? await item.load(.stringValue), !v.isEmpty { genre = v }
                    case .id3MetadataEncodedBy:
                        if let v = try? await item.load(.stringValue), !v.isEmpty { encoder = v }
                    default: break
                    }
                }
                if let iTunesKey = item.identifier {
                    switch iTunesKey {
                    case .iTunesMetadataTrackNumber:
                        if let v = try? await item.load(.numberValue) {
                            trackNumber = v.intValue
                        }
                    case .iTunesMetadataUserGenre, .iTunesMetadataPredefinedGenre:
                        if let v = try? await item.load(.stringValue), !v.isEmpty { genre = v }
                    default: break
                    }
                }
            }

            let tracks = try await asset.load(.tracks)
            for track in tracks {
                let mediaType = track.mediaType
                if mediaType == .audio {
                    if let desc = try? await track.load(.formatDescriptions).first,
                       let afd = desc as? CMAudioFormatDescription {
                        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(afd)
                        if let asbd {
                            sampleRate = Int(asbd.pointee.mSampleRate)
                            channels = Int(asbd.pointee.mChannelsPerFrame)
                        }
                    }
                    bitRate = Int((try? await track.load(.estimatedDataRate)) ?? 0) / 1000
                }
            }
        } catch {
            isIncomplete = true
        }

        if title == fileName && artist == "未知艺术家" { isIncomplete = true }

        return ParsedMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            format: ext,
            sampleRate: sampleRate,
            bitRate: bitRate,
            channels: channels,
            trackNumber: trackNumber,
            year: year,
            genre: genre,
            encoder: encoder,
            coverImage: coverImage,
            isIncomplete: isIncomplete
        )
    }
}
