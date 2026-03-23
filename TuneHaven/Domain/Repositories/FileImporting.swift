import Foundation

@MainActor
protocol FileImporting: AnyObject {
    func importFromFiles(urls: [URL], onProgress: @escaping @MainActor (ImportProgress) -> Void) async -> ImportResult
}
