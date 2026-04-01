import AVFoundation
import UIKit
import Foundation

final class AudioMetadataParser: AudioMetadataParsing {
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

        let durationResult = await parseDuration(asset: asset)
        duration = durationResult.duration
        if durationResult.isIncomplete { isIncomplete = true }

        let commonResult = await parseCommonMetadata(asset: asset, title: title, artist: artist, album: album)
        title = commonResult.title
        artist = commonResult.artist
        album = commonResult.album
        coverImageData = commonResult.coverImageData
        if commonResult.isIncomplete { isIncomplete = true }

        async let extFuture = parseExtendedMetadata(asset: asset)
        async let trackFuture = parseAudioTrackInfo(asset: asset)
        let extResult = await extFuture
        let trackResult = await trackFuture

        trackNumber = extResult.trackNumber ?? trackNumber
        year = extResult.year ?? year
        genre = extResult.genre ?? genre
        encoder = extResult.encoder ?? encoder
        if extResult.isIncomplete { isIncomplete = true }

        sampleRate = trackResult.sampleRate
        bitRate = trackResult.bitRate
        channels = trackResult.channels
        if trackResult.isIncomplete { isIncomplete = true }

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

    // MARK: - Private Parsing Methods

    private func parseDuration(asset: AVURLAsset) async -> (duration: TimeInterval, isIncomplete: Bool) {
        var duration: TimeInterval = 0
        var incomplete = false
        do {
            let cmDuration = try await asset.load(.duration)
            duration = cmDuration.seconds.isNaN ? 0 : cmDuration.seconds
        } catch {
            incomplete = true
            ErrorLogger.shared.log(.importReadFailed(asset.url.lastPathComponent),
                                   context: "AudioMetadataParser: duration 解析失败 - \(error.localizedDescription)")
        }
        return (duration, incomplete)
    }

    private func parseCommonMetadata(
        asset: AVURLAsset,
        title: String,
        artist: String,
        album: String
    ) async -> (title: String, artist: String, album: String, coverImageData: Data?, isIncomplete: Bool) {
        var title = title
        var artist = artist
        var album = album
        var coverImageData: Data?
        var isIncomplete = false

        do {
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
        } catch {
            isIncomplete = true
            ErrorLogger.shared.log(.importReadFailed(asset.url.lastPathComponent),
                                   context: "AudioMetadataParser: commonMetadata 解析失败 - \(error.localizedDescription)")
        }

        return (title, artist, album, coverImageData, isIncomplete)
    }

    private func parseExtendedMetadata(
        asset: AVURLAsset
    ) async -> (trackNumber: Int?, year: Int?, genre: String?, encoder: String?, isIncomplete: Bool) {
        var trackNumber: Int?
        var year: Int?
        var genre: String?
        var encoder: String?
        var isIncomplete = false

        do {
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
        } catch {
            isIncomplete = true
            ErrorLogger.shared.log(.importReadFailed(asset.url.lastPathComponent),
                                   context: "AudioMetadataParser: extendedMetadata 解析失败 - \(error.localizedDescription)")
        }

        return (trackNumber, year, genre, encoder, isIncomplete)
    }

    private func parseAudioTrackInfo(
        asset: AVURLAsset
    ) async -> (sampleRate: Int?, bitRate: Int?, channels: Int?, isIncomplete: Bool) {
        var sampleRate: Int?
        var bitRate: Int?
        var channels: Int?
        var isIncomplete = false

        do {
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
            ErrorLogger.shared.log(.importReadFailed(asset.url.lastPathComponent),
                                   context: "AudioMetadataParser: tracks 解析失败 - \(error.localizedDescription)")
        }

        return (sampleRate, bitRate, channels, isIncomplete)
    }
}
