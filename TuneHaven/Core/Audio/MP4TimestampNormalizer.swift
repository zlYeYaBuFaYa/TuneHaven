import Foundation

/// 把 MP4 / M4A 里 mvhd、tkhd、mdhd 的创建与修改时间清零。
///
/// `AVAssetExportSession` 每次导出都写入当时的时间，同一首歌导出两次字节不同、哈希也不同，
/// 入库时的哈希查重就拦不住重复。清零后同一来源每次导出的文件完全一致。
enum MP4TimestampNormalizer {
    private static let containers: Set<String> = ["moov", "trak", "mdia"]
    private static let timedBoxes: Set<String> = ["mvhd", "tkhd", "mdhd"]

    static func normalize(fileAt url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()

        var offset: UInt64 = 0
        while offset + 8 <= fileSize {
            try handle.seek(toOffset: offset)
            guard let head = try handle.read(upToCount: 16).map(Array.init),
                  let box = boxHeader(in: head, at: 0, limit: head.count) else { return }
            let size = box.size == 0 ? fileSize - offset : box.size
            guard size >= UInt64(box.headerLength), offset + size <= fileSize else { return }

            if box.type == "moov" {
                try handle.seek(toOffset: offset)
                guard size <= UInt64(Int.max),
                      var moov = try handle.read(upToCount: Int(size)).map(Array.init),
                      moov.count == Int(size) else { return }
                if zeroTimestamps(in: &moov, from: box.headerLength, to: moov.count) {
                    try handle.seek(toOffset: offset)
                    try handle.write(contentsOf: moov)
                }
                return
            }
            offset += size
        }
    }

    /// 返回是否改动了内容。
    private static func zeroTimestamps(in bytes: inout [UInt8], from start: Int, to end: Int) -> Bool {
        var changed = false
        var offset = start
        while offset + 8 <= end, let box = boxHeader(in: bytes, at: offset, limit: end - offset) {
            let size = box.size == 0 ? UInt64(end - offset) : box.size
            guard size >= UInt64(box.headerLength), size <= UInt64(end - offset) else { break }
            let boxEnd = offset + Int(size)
            let body = offset + box.headerLength

            if containers.contains(box.type) {
                changed = zeroTimestamps(in: &bytes, from: body, to: boxEnd) || changed
            } else if timedBoxes.contains(box.type), body < boxEnd {
                // 版本 1 是两个 64 位时间，版本 0 是两个 32 位时间，紧跟在版本与标志之后
                let length = bytes[body] == 1 ? 16 : 8
                let range = (body + 4)..<(body + 4 + length)
                if range.upperBound <= boxEnd {
                    for i in range where bytes[i] != 0 {
                        bytes[i] = 0
                        changed = true
                    }
                }
            }
            offset = boxEnd
        }
        return changed
    }

    private static func boxHeader(in bytes: [UInt8], at offset: Int, limit: Int) -> (size: UInt64, type: String, headerLength: Int)? {
        guard limit >= 8 else { return nil }
        let size32 = bytes[offset..<(offset + 4)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
        guard size32 == 1 else { return (size32, type, 8) }
        guard limit >= 16 else { return nil }
        let size64 = bytes[(offset + 8)..<(offset + 16)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return (size64, type, 16)
    }
}
