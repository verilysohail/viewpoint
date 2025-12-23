import Foundation

class Logger {
    static let shared = Logger()

    private let logFileURL: URL
    private let dateFormatter: DateFormatter
    private var fileHandle: FileHandle?
    private let logDirectory: URL

    // Log rotation settings
    private let maxLogFileSize: UInt64 = 1 * 1024 * 1024 // 1 MB
    private let maxRotatedFiles: Int = 3 // Keep 3 old log files
    private var messagesSinceLastCheck = 0
    private let checkInterval = 100 // Check file size every 100 log messages

    private init() {
        // Create log file in app's container
        let containerURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logDirectory = containerURL.appendingPathComponent("Viewpoint", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        logFileURL = logDirectory.appendingPathComponent("viewpoint.log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Check for rotation on startup (before opening file handle)
        rotateLogsOnStartupIfNeeded()

        // Create or open log file
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        // Log startup
        log("=== Viewpoint started ===", level: .info)
        log("Log file: \(logFileURL.path)", level: .info)
    }

    private func rotateLogsOnStartupIfNeeded() {
        guard FileManager.default.fileExists(atPath: logFileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize >= maxLogFileSize else {
            return
        }

        // Rotate log files on startup
        // Delete oldest log file if it exists
        let oldestLogURL = logDirectory.appendingPathComponent("viewpoint.log.\(maxRotatedFiles)")
        try? FileManager.default.removeItem(at: oldestLogURL)

        // Rename existing rotated logs
        for i in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let sourceURL = logDirectory.appendingPathComponent("viewpoint.log.\(i)")
            let destURL = logDirectory.appendingPathComponent("viewpoint.log.\(i + 1)")
            try? FileManager.default.moveItem(at: sourceURL, to: destURL)
        }

        // Rename current log to viewpoint.log.1
        let rotatedLogURL = logDirectory.appendingPathComponent("viewpoint.log.1")
        try? FileManager.default.moveItem(at: logFileURL, to: rotatedLogURL)

        print("Log rotated on startup: \(fileSize) bytes -> viewpoint.log.1")
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

        // Check if rotation is needed (every N messages to avoid excessive file stat calls)
        messagesSinceLastCheck += 1
        if messagesSinceLastCheck >= checkInterval {
            messagesSinceLastCheck = 0
            rotateLogsIfNeeded()
        }

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

    func getLogFiles() -> [(name: String, size: UInt64, url: URL)] {
        var logFiles: [(name: String, size: UInt64, url: URL)] = []

        // Add current log file
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let fileSize = attributes[.size] as? UInt64 {
            logFiles.append((name: "viewpoint.log (current)", size: fileSize, url: logFileURL))
        }

        // Add rotated log files
        for i in 1...maxRotatedFiles {
            let rotatedURL = logDirectory.appendingPathComponent("viewpoint.log.\(i)")
            if let attributes = try? FileManager.default.attributesOfItem(atPath: rotatedURL.path),
               let fileSize = attributes[.size] as? UInt64 {
                logFiles.append((name: "viewpoint.log.\(i)", size: fileSize, url: rotatedURL))
            }
        }

        return logFiles
    }

    func clearLog() {
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== Log cleared ===", level: .info)
    }

    func clearAllLogs() {
        // Clear current log
        clearLog()

        // Delete all rotated logs
        for i in 1...maxRotatedFiles {
            let rotatedURL = logDirectory.appendingPathComponent("viewpoint.log.\(i)")
            try? FileManager.default.removeItem(at: rotatedURL)
        }

        log("=== All logs cleared ===", level: .info)
    }

    private func rotateLogsIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? UInt64 else {
            return
        }

        // Check if log file exceeds max size
        guard fileSize >= maxLogFileSize else {
            return
        }

        // Close current file handle
        try? fileHandle?.synchronize()
        try? fileHandle?.close()
        fileHandle = nil

        // Rotate log files
        // Delete oldest log file if it exists (viewpoint.log.N)
        let oldestLogURL = logDirectory.appendingPathComponent("viewpoint.log.\(maxRotatedFiles)")
        try? FileManager.default.removeItem(at: oldestLogURL)

        // Rename existing rotated logs (viewpoint.log.N-1 -> viewpoint.log.N)
        for i in stride(from: maxRotatedFiles - 1, through: 1, by: -1) {
            let sourceURL = logDirectory.appendingPathComponent("viewpoint.log.\(i)")
            let destURL = logDirectory.appendingPathComponent("viewpoint.log.\(i + 1)")
            try? FileManager.default.moveItem(at: sourceURL, to: destURL)
        }

        // Rename current log to viewpoint.log.1
        let rotatedLogURL = logDirectory.appendingPathComponent("viewpoint.log.1")
        try? FileManager.default.moveItem(at: logFileURL, to: rotatedLogURL)

        // Create new log file
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)

        // Reopen file handle
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()

        // Log rotation event
        let timestamp = dateFormatter.string(from: Date())
        let rotationMessage = "[\(timestamp)] [INFO] [Logger.swift] === Log rotated (previous log archived to viewpoint.log.1) ===\n"
        if let data = rotationMessage.data(using: .utf8) {
            fileHandle?.write(data)
        }
        print("Log rotated: \(fileSize) bytes -> viewpoint.log.1")
    }

    deinit {
        try? fileHandle?.close()
    }
}
