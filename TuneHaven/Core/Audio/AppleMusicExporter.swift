import AVFoundation
import CoreMedia

/// 把 Apple Music 本地歌曲（`ipod-library://`）导出成临时文件。
///
/// 系统不给第三方 App 原始文件路径，只能经 AVFoundation 读出来再写一份。
/// 按编码选择导出方式，优先原样写出，不重新编码：
/// - AAC / ALAC：原样导出为 m4a
/// - MP3：`AVAssetExportSession` 不能原样写 mp3，改用 `AVAssetReader` 逐帧拷出压缩数据，
///   再补上 ID3 标签（来自 `tags`）和 Xing 信息帧
/// - PCM：原样导出为 wav
/// 以上都失败时才转码为 AAC，并在结果里标记 `transcoded`。
/// m4a 导出后清零时间戳，同一首歌每次导出字节一致，入库时的哈希查重才能拦住重复。
enum AppleMusicExporter {
    struct Output: Sendable {
        let url: URL
        let fileExtension: String
        let transcoded: Bool
    }

    static func export(assetURL: URL, to directory: URL, tags: MP3Tags = MP3Tags()) async -> Output? {
        let asset = AVURLAsset(url: assetURL)

        switch await audioCodec(of: asset) {
        case kAudioFormatMPEGLayer3:
            if let url = await extractRawMP3(asset: asset, tags: tags, to: tempURL(in: directory, ext: "mp3")) {
                return Output(url: url, fileExtension: "mp3", transcoded: false)
            }
        case kAudioFormatLinearPCM:
            if let url = await runExportSession(asset, to: tempURL(in: directory, ext: "wav"), as: .wav, preset: AVAssetExportPresetPassthrough) {
                return Output(url: url, fileExtension: "wav", transcoded: false)
            }
        default:
            break
        }

        if let url = await runExportSession(asset, to: tempURL(in: directory, ext: "m4a"), as: .m4a, preset: AVAssetExportPresetPassthrough),
           normalizeTimestamps(of: url) {
            return Output(url: url, fileExtension: "m4a", transcoded: false)
        }
        if let url = await runExportSession(asset, to: tempURL(in: directory, ext: "caf"), as: .caf, preset: AVAssetExportPresetPassthrough) {
            return Output(url: url, fileExtension: "caf", transcoded: false)
        }
        if let url = await runExportSession(asset, to: tempURL(in: directory, ext: "m4a"), as: .m4a, preset: AVAssetExportPresetAppleM4A),
           normalizeTimestamps(of: url) {
            return Output(url: url, fileExtension: "m4a", transcoded: true)
        }
        return nil
    }

    // MARK: - Private

    private static func tempURL(in directory: URL, ext: String) -> URL {
        directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    private static func audioCodec(of asset: AVURLAsset) async -> AudioFormatID? {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let description = try? await track.load(.formatDescriptions).first else {
            return nil
        }
        return CMFormatDescriptionGetMediaSubType(description)
    }

    private static func normalizeTimestamps(of url: URL) -> Bool {
        do {
            try MP4TimestampNormalizer.normalize(fileAt: url)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    private static func runExportSession(_ asset: AVURLAsset, to url: URL, as fileType: AVFileType, preset: String) async -> URL? {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        do {
            try await session.export(to: url, as: fileType)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// MP3 的每个压缩包就是带帧头的 MPEG 音频帧，按顺序写出即是可播放的 mp3。
    /// 文件布局：ID3 标签 → Xing 信息帧（先占位，写完音频帧后回填）→ 音频帧。
    private static func extractRawMP3(asset: AVURLAsset, tags: MP3Tags, to url: URL) async -> URL? {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            do {
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                output.alwaysCopiesSampleData = false
                reader.add(output)
                guard reader.startReading(),
                      FileManager.default.createFile(atPath: url.path, contents: nil) else { return nil }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }

                let id3 = ID3v2TagBuilder.build(tags)
                try handle.write(contentsOf: id3)

                var xing: MP3XingFrame?
                var frameSizes: [Int] = []
                var isFirstPacket = true
                while let sampleBuffer = output.copyNextSampleBuffer() {
                    guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                    let length = CMBlockBufferGetDataLength(block)
                    var data = Data(count: length)
                    let status = data.withUnsafeMutableBytes { buffer in
                        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: buffer.baseAddress!)
                    }
                    guard status == kCMBlockBufferNoErr else { throw CocoaError(.fileWriteUnknown) }

                    if isFirstPacket {
                        isFirstPacket = false
                        xing = MP3XingFrame(firstFrameHeader: Array(data.prefix(4)))
                        if let xing { try handle.write(contentsOf: Data(count: xing.frameLength)) }
                    }
                    frameSizes.append(contentsOf: packetSizes(of: sampleBuffer, totalLength: length))
                    try handle.write(contentsOf: data)
                }
                guard reader.status == .completed else { throw reader.error ?? CocoaError(.fileReadUnknown) }

                if let xing {
                    try handle.seek(toOffset: UInt64(id3.count))
                    try handle.write(contentsOf: xing.build(frameSizes: frameSizes))
                }
                return url
            } catch {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
        }.value
    }

    /// 一个 sample buffer 可能装着多个 MPEG 帧，逐个取出大小；取不到时整块算一帧。
    private static func packetSizes(of sampleBuffer: CMSampleBuffer, totalLength: Int) -> [Int] {
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 1 else { return [totalLength] }
        let sizes = (0..<count).map { CMSampleBufferGetSampleSize(sampleBuffer, at: $0) }
        return sizes.reduce(0, +) == totalLength ? sizes : [totalLength]
    }
}
