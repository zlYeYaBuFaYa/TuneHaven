import Foundation

@MainActor
protocol WiFiFileImporting: AnyObject {
    /// 导入或备份正在进行，此时调用导入会被拒绝
    var isImportBusy: Bool { get }
    func processWiFiFile(tempURL: URL, originalFilename: String) async -> SingleImportResult
}
