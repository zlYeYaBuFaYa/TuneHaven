import Foundation

/// 只读写 ZIP store（method 0）。音频本身已压缩，备份包不需要 deflate。
enum ZipStoreArchive {
    struct DataEntry: Sendable {
        var name: String
        var data: Data
    }

    static func zipDirectory(at source: URL, to destination: URL, isCancelled: () -> Bool = { false }) throws {
        let files = try collectFiles(root: source)
        var entries: [(name: String, url: URL)] = []
        entries.reserveCapacity(files.count)
        for file in files {
            if isCancelled() { throw AppError.backupCancelled }
            let name = try relativeName(of: file, root: source)
            try validateEntryName(name)
            entries.append((name, file))
        }
        try writeFileEntries(entries, to: destination, isCancelled: isCancelled)
    }

    /// 测试用来构造非法路径。正式导出走 `zipDirectory`，路径来自沙盒内的相对文件名。
    static func writeDataEntries(_ entries: [DataEntry], to destination: URL, validateNames: Bool) throws {
        if validateNames {
            for entry in entries {
                try validateEntryName(entry.name)
            }
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        fileManager.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var central = Data()
        var count = 0
        var offset: UInt64 = 0
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            guard nameData.count <= Int(UInt16.max) else {
                throw AppError.backupInvalidPackage("文件名过长")
            }
            let size = UInt64(entry.data.count)
            try ensureOffset(offset, adding: size)
            let crc = ZIPCRC32.checksum(entry.data)
            let local = localHeader(name: nameData, crc: crc, size: UInt32(size))
            try handle.write(contentsOf: local)
            try handle.write(contentsOf: entry.data)
            appendCentral(
                to: &central,
                name: nameData,
                crc: crc,
                size: UInt32(size),
                localOffset: UInt32(offset)
            )
            offset += UInt64(local.count + entry.data.count)
            count += 1
        }
        try finish(handle: handle, central: central, count: count, offset: offset)
    }

    static func unzip(_ archive: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }

        while true {
            let signatureData = try handle.read(upToCount: 4) ?? Data()
            if signatureData.isEmpty { return }
            guard signatureData.count == 4 else {
                throw AppError.backupInvalidPackage("备份包已损坏")
            }
            let signature = readUInt32(signatureData, 0)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                return
            }
            guard signature == 0x04034b50 else {
                throw AppError.backupInvalidPackage("备份包已损坏")
            }
            let header = try readExactly(handle, count: 26)
            let flags = readUInt16(header, 2)
            let method = readUInt16(header, 4)
            let crc = readUInt32(header, 10)
            let compressedSize = readUInt32(header, 14)
            let uncompressedSize = readUInt32(header, 18)
            let nameLength = Int(readUInt16(header, 22))
            let extraLength = Int(readUInt16(header, 24))
            if flags & 0x8 != 0 || method != 0 || compressedSize != uncompressedSize {
                throw AppError.backupInvalidPackage("备份包使用了不支持的压缩方式")
            }
            let nameData = try readExactly(handle, count: nameLength)
            if extraLength > 0 {
                _ = try readExactly(handle, count: extraLength)
            }
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw AppError.backupInvalidPackage("备份包文件名无法识别")
            }
            try validateEntryName(name)
            let output = try safeDestination(root: destination, entry: name)
            try fileManager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let actualCRC = try stream(handle, count: UInt64(uncompressedSize), to: output)
            if actualCRC != crc {
                try? fileManager.removeItem(at: output)
                throw AppError.backupInvalidPackage("备份包校验失败")
            }
        }
    }

    static func validateEntryName(_ name: String) throws {
        if name.isEmpty || name.hasPrefix("/") || name.hasPrefix("\\") || name.contains("\\") || name.contains(":") {
            throw AppError.backupInvalidPackage("备份包包含非法路径")
        }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
            throw AppError.backupInvalidPackage("备份包包含非法路径")
        }
    }

    // MARK: - Write

    private static func writeFileEntries(
        _ entries: [(name: String, url: URL)],
        to destination: URL,
        isCancelled: () -> Bool
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var central = Data()
        var offset: UInt64 = 0
        var count = 0
        if entries.count > Int(UInt16.max) {
            throw AppError.backupInvalidPackage("备份条目过多")
        }
        for entry in entries {
            if isCancelled() {
                try? FileManager.default.removeItem(at: destination)
                throw AppError.backupCancelled
            }
            let measured = try ZIPCRC32.checksum(file: entry.url)
            try ensureOffset(offset, adding: measured.size)
            let nameData = Data(entry.name.utf8)
            guard nameData.count <= Int(UInt16.max) else {
                throw AppError.backupInvalidPackage("文件名过长")
            }
            let local = localHeader(name: nameData, crc: measured.crc, size: UInt32(measured.size))
            try handle.write(contentsOf: local)
            try streamFile(at: entry.url, to: handle)
            appendCentral(
                to: &central,
                name: nameData,
                crc: measured.crc,
                size: UInt32(measured.size),
                localOffset: UInt32(offset)
            )
            offset += UInt64(local.count) + measured.size
            count += 1
        }
        try finish(handle: handle, central: central, count: count, offset: offset)
    }

    private static func finish(handle: FileHandle, central: Data, count: Int, offset: UInt64) throws {
        guard offset <= UInt64(UInt32.max), central.count <= Int(UInt32.max), count <= Int(UInt16.max) else {
            throw AppError.backupInvalidPackage("备份超过 4GB，请关闭「包含音频」后重试")
        }
        try handle.write(contentsOf: central)
        var eocd = Data()
        appendUInt32(0x06054b50, to: &eocd)
        appendUInt16(0, to: &eocd)
        appendUInt16(0, to: &eocd)
        appendUInt16(UInt16(count), to: &eocd)
        appendUInt16(UInt16(count), to: &eocd)
        appendUInt32(UInt32(central.count), to: &eocd)
        appendUInt32(UInt32(offset), to: &eocd)
        appendUInt16(0, to: &eocd)
        try handle.write(contentsOf: eocd)
    }

    private static func localHeader(name: Data, crc: UInt32, size: UInt32) -> Data {
        var data = Data()
        appendUInt32(0x04034b50, to: &data)
        appendUInt16(20, to: &data)
        appendUInt16(1 << 11, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(crc, to: &data)
        appendUInt32(size, to: &data)
        appendUInt32(size, to: &data)
        appendUInt16(UInt16(name.count), to: &data)
        appendUInt16(0, to: &data)
        data.append(name)
        return data
    }

    private static func appendCentral(to data: inout Data, name: Data, crc: UInt32, size: UInt32, localOffset: UInt32) {
        appendUInt32(0x02014b50, to: &data)
        appendUInt16(20, to: &data)
        appendUInt16(20, to: &data)
        appendUInt16(1 << 11, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(crc, to: &data)
        appendUInt32(size, to: &data)
        appendUInt32(size, to: &data)
        appendUInt16(UInt16(name.count), to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(0, to: &data)
        appendUInt32(localOffset, to: &data)
        data.append(name)
    }

    private static func ensureOffset(_ offset: UInt64, adding size: UInt64) throws {
        let maxOffset = UInt64(UInt32.max) - 65_536
        let next = offset + size + 30
        if next > maxOffset || offset > UInt64(UInt32.max) {
            throw AppError.backupInvalidPackage("备份超过 4GB，请关闭「包含音频」后重试")
        }
    }

    // MARK: - Read

    private static func safeDestination(root: URL, entry: String) throws -> URL {
        let destination = root.appendingPathComponent(entry)
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path != rootPath && !path.hasPrefix(prefix) {
            throw AppError.backupInvalidPackage("备份包包含非法路径")
        }
        return destination
    }

    private static func stream(_ handle: FileHandle, count: UInt64, to destination: URL) throws -> UInt32 {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var remaining = count
        var crc: UInt32 = 0xFFFF_FFFF
        while remaining > 0 {
            let chunkSize = Int(min(remaining, 1024 * 1024))
            let chunk = try readExactly(handle, count: chunkSize)
            try output.write(contentsOf: chunk)
            crc = ZIPCRC32.update(crc, with: chunk)
            remaining -= UInt64(chunk.count)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func streamFile(at url: URL, to handle: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        while true {
            let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { return }
            try handle.write(contentsOf: chunk)
        }
    }

    private static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else {
            throw AppError.backupInvalidPackage("备份包已损坏")
        }
        return data
    }

    // MARK: - Paths

    private static func collectFiles(root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                files.append(contentsOf: try collectFiles(root: child))
            } else {
                files.append(child)
            }
        }
        return files
    }

    private static func relativeName(of file: URL, root: URL) throws -> String {
        let prefix = directoryPrefix(root)
        let path = file.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(prefix) else {
            throw AppError.backupInvalidPackage("无法定位备份文件")
        }
        return String(path.dropFirst(prefix.count)).replacingOccurrences(of: "\\", with: "/")
    }

    private static func directoryPrefix(_ root: URL) -> String {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasSuffix("/") ? path : path + "/"
    }

    // MARK: - Binary

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset])
            | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}

enum ZIPCRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        update(0xFFFF_FFFF, with: data) ^ 0xFFFF_FFFF
    }

    static func checksum(file url: URL) throws -> (crc: UInt32, size: UInt64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var crc: UInt32 = 0xFFFF_FFFF
        var size: UInt64 = 0
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            crc = update(crc, with: chunk)
            size += UInt64(chunk.count)
            if size > UInt64(UInt32.max) {
                throw AppError.backupInvalidPackage("单个文件超过 4GB")
            }
        }
        return (crc ^ 0xFFFF_FFFF, size)
    }

    static func update(_ crc: UInt32, with data: Data) -> UInt32 {
        var value = crc
        for byte in data {
            let index = Int((value ^ UInt32(byte)) & 0xFF)
            value = table[index] ^ (value >> 8)
        }
        return value
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xEDB88320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }
}
