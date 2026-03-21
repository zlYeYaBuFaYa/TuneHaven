import UniformTypeIdentifiers

extension UTType {
    static let flac = UTType("org.xiph.flac") ?? UTType(filenameExtension: "flac") ?? .audio
    static let alac = UTType(filenameExtension: "alac") ?? .audio
    static let caf = UTType(filenameExtension: "caf") ?? .audio

    /// 与 FileStorageService.supportedExtensions 保持一致的 UTType 列表。
    /// 新增格式时需同步更新两处。
    static let allSupportedAudio: [UTType] = [
        .mp3, .mpeg4Audio, .flac, .alac, .wav, .aiff, .caf
    ]
}
