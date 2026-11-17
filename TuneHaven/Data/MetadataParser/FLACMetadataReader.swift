import Foundation

/// Native FLAC metadata blocks, RFC 9639 §8. Reads headers only, never the audio payload.
struct FLACMetadataReader {
    var tags: [String: String] = [:]
    var coverImageData: Data?
    var sampleRate: Int?
    var channels: Int?
    var duration: TimeInterval?

    static func read(url: URL) -> Self? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard (try? file.read(upToCount: 4)) == Data("fLaC".utf8) else { return nil }
        var result = Self()
        var hasFrontCover = false
        var metadataBytes = 0
        // Bound both work and allocation for malformed/untrusted imports.
        for _ in 0..<1024 {
            guard let header = try? file.read(upToCount: 4), header.count == 4 else { break }
            let type = header[0] & 0x7f
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            metadataBytes += length + 4
            guard metadataBytes <= 64 * 1024 * 1024 else { break }
            if type == 0 || type == 4 || type == 6 {
                guard let data = try? file.read(upToCount: length), data.count == length else { break }
                switch type {
                case 0 where data.count == 34:
                    let packed = data[10..<18].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                    let rate = Int(packed >> 44)
                    result.sampleRate = rate > 0 ? rate : nil
                    result.channels = Int((packed >> 41) & 7) + 1
                    let samples = packed & 0xfffffffff
                    if rate > 0, samples > 0 { result.duration = Double(samples) / Double(rate) }
                case 4:
                    if let tags = comments(data) { result.tags.merge(tags) { old, _ in old } }
                case 6:
                    if let picture = picture(data), !hasFrontCover {
                        result.coverImageData = picture.data
                        hasFrontCover = picture.isFront
                    }
                default: break
                }
            } else {
                guard let offset = try? file.offset(),
                      (try? file.seek(toOffset: offset + UInt64(length))) != nil else { break }
            }
            if header[0] & 0x80 != 0 { break }
        }
        return result
    }

    private static func comments(_ data: Data) -> [String: String]? {
        var reader = Cursor(data: data)
        guard let vendorLength = reader.integer(littleEndian: true), reader.skip(vendorLength),
              let count = reader.integer(littleEndian: true), count <= reader.remaining / 4 else { return nil }
        var tags: [String: String] = [:]
        for _ in 0..<count {
            guard let length = reader.integer(littleEndian: true), let bytes = reader.bytes(length),
                  let field = String(data: bytes, encoding: .utf8), let equals = field.firstIndex(of: "=") else { return nil }
            let key = field[..<equals].uppercased()
            let value = field[field.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, tags[key] == nil { tags[key] = value }
        }
        return tags
    }

    private static func picture(_ data: Data) -> (data: Data, isFront: Bool)? {
        var reader = Cursor(data: data)
        guard let type = reader.integer(), let mimeLength = reader.integer(), let mime = reader.bytes(mimeLength),
              String(data: mime, encoding: .utf8)?.hasPrefix("image/") == true,
              let descriptionLength = reader.integer(), reader.skip(descriptionLength),
              reader.skip(16), let length = reader.integer(), length > 0, let image = reader.bytes(length) else { return nil }
        return (image, type == 3)
    }

    private struct Cursor {
        let data: Data
        var offset = 0
        var remaining: Int { data.count - offset }
        mutating func bytes(_ count: Int) -> Data? {
            guard count >= 0, count <= remaining else { return nil }
            defer { offset += count }
            return data.subdata(in: offset..<(offset + count))
        }
        mutating func skip(_ count: Int) -> Bool {
            guard count >= 0, count <= remaining else { return false }
            offset += count
            return true
        }
        mutating func integer(littleEndian: Bool = false) -> Int? {
            guard let bytes = bytes(4) else { return nil }
            return (littleEndian ? Array(bytes.reversed()) : Array(bytes)).reduce(0) { $0 << 8 | Int($1) }
        }
    }
}
