import Foundation
import Testing
@testable import TuneHaven

@Suite("备份包：单遍写入与解包取消")
struct ZipStreamingTests {
    @Test("多条目（含空文件和超过 1MB 的文件）写入后 CRC 与内容都正确")
    func multiEntryRoundTrip() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("audio", isDirectory: true), withIntermediateDirectories: true)
        let big = Data((0..<(3 * 1024 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let files: [String: Data] = [
            "a.json": Data("{}".utf8),
            "audio/空.mp3": Data(),
            "audio/大.flac": big,
        ]
        for (name, data) in files { try data.write(to: source.appendingPathComponent(name)) }
        let zip = root.appendingPathComponent("pack.tunehaven")

        try ZipStoreArchive.zipDirectory(at: source, to: zip)
        let out = root.appendingPathComponent("out", isDirectory: true)
        try ZipStoreArchive.unzip(zip, to: out)

        for (name, data) in files {
            #expect(try Data(contentsOf: out.appendingPathComponent(name)) == data)
        }
    }

    @Test("解包大条目途中取消：立即停止并抛出取消")
    func unzipCancelsMidEntry() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(count: 4 * 1024 * 1024).write(to: source.appendingPathComponent("big.mp3"))
        let zip = root.appendingPathComponent("pack.tunehaven")
        try ZipStoreArchive.zipDirectory(at: source, to: zip)

        var checks = 0
        #expect(throws: AppError.self) {
            try ZipStoreArchive.unzip(zip, to: root.appendingPathComponent("out", isDirectory: true)) {
                checks += 1
                return checks > 2
            }
        }
        // 第一个条目开始前 1 次，之后按 1MB 块检查；4MB 的条目只写了一块就停
        #expect(checks == 3)
    }

    @Test("打包途中取消：抛出取消")
    func zipCancelsMidFile() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(count: 4 * 1024 * 1024).write(to: source.appendingPathComponent("big.mp3"))

        var checks = 0
        #expect(throws: AppError.self) {
            try ZipStoreArchive.zipDirectory(at: source, to: root.appendingPathComponent("pack.tunehaven")) {
                checks += 1
                return checks > 3
            }
        }
    }
}
