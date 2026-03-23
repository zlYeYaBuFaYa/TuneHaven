import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info  = "INFO"
    case error = "ERROR"
}

final class AppLogger {
    static let shared = AppLogger()

    private let writer = FileLogWriter(
        queueLabel: "com.tunehaven.applogger",
        fileURL: { SandboxPathManager.documentsURL.appendingPathComponent("app.log") }
    )

    private init() {}

    func debug(_ message: String, file: String = #file, function: String = #function) {
        writeLog(level: .debug, message: message, file: file, function: function)
    }

    func info(_ message: String, file: String = #file, function: String = #function) {
        writeLog(level: .info, message: message, file: file, function: function)
    }

    func error(_ message: String, file: String = #file, function: String = #function) {
        writeLog(level: .error, message: message, file: file, function: function)
    }

    func error(_ err: Error, context: String, file: String = #file, function: String = #function) {
        let msg = "\(context) - \(err.localizedDescription)"
        writeLog(level: .error, message: msg, file: file, function: function)
    }

    func error(_ err: AppError, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        let msg = "[\(err.errorCode)] \(context) - \(err.localizedDescription)"
        writeLog(level: .error, message: msg, file: file, function: function)
        ErrorLogger.shared.log(err, context: context, file: file, line: line)
    }

    private func writeLog(level: LogLevel, message: String, file: String, function: String) {
        let shortFile = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        let entry = "[\(FileLogWriter.isoDate())] [\(level.rawValue)] [\(shortFile).\(function)] \(message)\n"
        #if DEBUG
        print(entry, terminator: "")
        #endif
        writer.write(entry)
    }
}
