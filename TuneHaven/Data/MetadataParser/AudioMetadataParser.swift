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
    let coverImageData: Data?
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
        var artist = SongDefaults.unknownArtist
        var album = SongDefaults.unknownAlbum
        var duration: TimeInterval = 0
        var trackNumber: Int?
        var year: Int?
        var genre: String?
        var coverImageData: Data?
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
                    do {
                        if let v = try await item.load(.stringValue), !v.isEmpty { title = v }
                    } catch {
                        #if DEBUG
                        AppLogger.shared.debug("metadata title 解析失败: \(error)")
                        #endif
                    }
                case .commonKeyArtist:
                    do {
                        if let v = try await item.load(.stringValue), !v.isEmpty { artist = v }
                    } catch {
                        #if DEBUG
                        AppLogger.shared.debug("metadata artist 解析失败: \(error)")
                        #endif
                    }
                case .commonKeyAlbumName:
                    do {
                        if let v = try await item.load(.stringValue), !v.isEmpty { album = v }
                    } catch {
                        #if DEBUG
                        AppLogger.shared.debug("metadata album 解析失败: \(error)")
                        #endif
                    }
                case .commonKeyArtwork:
                    do {
                        if let data = try await item.load(.dataValue) {
                            coverImageData = data
                        }
                    } catch {
                        #if DEBUG
                        AppLogger.shared.debug("metadata artwork 解析失败: \(error)")
                        #endif
                    }
                default: break
                }
            }

            let allMetadata = try await asset.load(.metadata)
            for item in allMetadata {
                guard let identifier = item.identifier else { continue }
                do {
                    switch identifier {
                    case .id3MetadataTrackNumber:
                        if let v = try await item.load(.stringValue) {
                            trackNumber = Int(v.components(separatedBy: "/").first ?? v)
                        }
                    case .id3MetadataYear, .id3MetadataRecordingTime:
                        if let v = try await item.load(.stringValue) {
                            year = Int(v.prefix(4))
                        }
                    case .id3MetadataContentType:
                        if let v = try await item.load(.stringValue), !v.isEmpty { genre = v }
                    case .id3MetadataEncodedBy:
                        if let v = try await item.load(.stringValue), !v.isEmpty { encoder = v }
                    case .iTunesMetadataTrackNumber:
                        if let v = try await item.load(.numberValue) {
                            trackNumber = v.intValue
                        }
                    case .iTunesMetadataUserGenre, .iTunesMetadataPredefinedGenre:
                        if let v = try await item.load(.stringValue), !v.isEmpty { genre = v }
                    default: break
                    }
                } catch {
                    #if DEBUG
                    AppLogger.shared.debug("metadata \(identifier.rawValue) 解析失败: \(error)")
                    #endif
                }
            }

            let tracks = try await asset.load(.tracks)
            for track in tracks {
                let mediaType = track.mediaType
                if mediaType == .audio {
                    do {
                        if let desc = try await track.load(.formatDescriptions).first,
                           let afd = desc as? CMAudioFormatDescription {
                            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(afd)
                            if let asbd {
                                sampleRate = Int(asbd.pointee.mSampleRate)
                                channels = Int(asbd.pointee.mChannelsPerFrame)
                            }
                        }
                    } catch {
                        #if DEBUG
                        AppLogger.shared.debug("audio formatDescriptions 解析失败: \(error)")
                        #endif
                    }
                    do {
                        bitRate = Int(try await track.load(.estimatedDataRate)) / 1000
                    } catch {
                        #if DEBUG
                        AppLogger.shared.debug("audio estimatedDataRate 解析失败: \(error)")
                        #endif
                    }
                }
            }
        } catch {
            isIncomplete = true
            ErrorLogger.shared.log(.importFailed(url.lastPathComponent, error.localizedDescription),
                                   context: "AudioMetadataParser: 元数据解析不完整")
        }

        if title == fileName && artist == SongDefaults.unknownArtist { isIncomplete = true }

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
            coverImageData: coverImageData,
            isIncomplete: isIncomplete
        )
    }
}
