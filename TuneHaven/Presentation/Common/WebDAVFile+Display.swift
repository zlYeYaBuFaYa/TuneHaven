import Foundation

extension WebDAVFile {
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: contentLength, countStyle: .file)
    }
}
