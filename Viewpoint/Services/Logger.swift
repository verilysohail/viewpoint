import Foundation

class Logger {
    static let shared = Logger()

    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private let fileHandle: FileHandle?

    private init() {
        // Create log file in app's container
        let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupportURL = containerURL.appendingPathComponent("Viewpoint", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        logFileURL = appSupportURL.appendingPathComponent("viewpoint.log")

        // Create or open log file
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Log startup
        log("=== Viewpoint started ===", level: .info)
        log("Log file: \(logFileURL.path)", level: .info)
    }

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let filename = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(filename):\(line)] \(message)\n"

        // Write to console
        print(logMessage.trimmingCharacters(in: .newlines))

        // Write to file
        if let data = logMessage.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    func getLogFileURL() -> URL {
        return logFileURL
    }

    func getLogContents() -> String? {
        try? String(contentsOf: logFileURL, encoding: .utf8)
    }

    func clearLog() {
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== Log cleared ===", level: .info)
    }

    deinit {
        try? fileHandle?.close()
    }
}
