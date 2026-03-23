import Foundation

final class ErrorLogger {
    static let shared = ErrorLogger()

    private let writer = FileLogWriter(
        queueLabel: "com.tunehaven.errorlogger",
        fileURL: { SandboxPathManager.documentsURL.appendingPathComponent("error.log") }
    )

    private init() {}

    func log(_ error: AppError, context: String, file: String = #file, line: Int = #line) {
        let shortFile = (file as NSString).lastPathComponent
        let entry = "[\(FileLogWriter.isoDate())] [\(error.errorCode)] \(context) - \(error.localizedDescription) at \(shortFile):\(line)\n"
        writer.write(entry)
    }

    func logGeneric(_ error: Error, context: String) {
        let entry = "[\(FileLogWriter.isoDate())] [GEN] \(context) - \(error.localizedDescription)\n"
        writer.write(entry)
    }
}
