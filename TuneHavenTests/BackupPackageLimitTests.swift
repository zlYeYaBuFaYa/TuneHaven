import Foundation
import Testing
@testable import TuneHaven

@Suite("备份包体积与压缩限制")
struct BackupPackageLimitTests {
    @Test("声明体积超过 ZIP32 上限时拒绝导出")
    func testRejectsPayloadOver4GB() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        var draft = BackupTestFiles.draft()
        draft.catalog.manifest.payloadBytes = Int64(BackupPackageFormat.maxZipOffset) + 1
        let zip = root.appendingPathComponent("huge.tunehaven")
        do {
            try BackupPackageCodec.write(draft: draft, to: zip, stagingParent: root)
            Issue.record("超过 4GB 的包应该被拒绝")
        } catch let error as AppError {
            #expect(error == .backupInvalidPackage("备份超过 4GB，请关闭「包含音频」后重试"))
        } catch {
            Issue.record("意外错误 \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: zip.path))
    }

    @Test("声明体积等于 ZIP32 上限时仍可写入")
    func testAllowsPayloadAt4GBLimit() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        var draft = BackupTestFiles.draft()
        draft.catalog.manifest.payloadBytes = Int64(BackupPackageFormat.maxZipOffset)
        let zip = root.appendingPathComponent("edge.tunehaven")
        try BackupPackageCodec.write(draft: draft, to: zip, stagingParent: root)
        #expect(FileManager.default.fileExists(atPath: zip.path))
    }

    @Test("deflate 压缩的包会被拒绝")
    func testRejectsDeflateCompression() throws {
        let root = try BackupTestFiles.makeRoot()
        defer { BackupTestFiles.remove(root) }
        let zip = root.appendingPathComponent("deflate.tunehaven")
        try ZipStoreArchive.writeDataEntries(
            [ZipStoreArchive.DataEntry(name: "manifest.json", data: Data("{}".utf8))],
            to: zip,
            validateNames: true
        )
        var bytes = try Data(contentsOf: zip)
        #expect(bytes.count > 10)
        #expect(bytes[8] == 0 && bytes[9] == 0)
        bytes[8] = 8
        try bytes.write(to: zip)
        let output = root.appendingPathComponent("out", isDirectory: true)
        do {
            try ZipStoreArchive.unzip(zip, to: output)
            Issue.record("非 store 压缩应该被拒绝")
        } catch let error as AppError {
            #expect(error == .backupInvalidPackage("备份包使用了不支持的压缩方式"))
        } catch {
            Issue.record("意外错误 \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("manifest.json").path))
    }
}
