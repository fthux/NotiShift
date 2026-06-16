import Foundation
import OSLog

enum LogLevel: String {
  case info = "INFO"
  case debug = "DEBUG"
  case error = "ERROR"
}

final class AppLogger {
  static let shared = AppLogger()

  private let logger = Logger(subsystem: AppConstants.subsystem, category: "app")
  let logFileURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/NotiShift.log")

  private var debugEnabled: Bool {
    NotiShiftPreferences.shared.debugLoggingEnabled
  }

  private init() {
    prepareLogFile()
  }

  func info(_ message: String) {
    log(.info, message)
  }

  func debug(_ message: String) {
    guard debugEnabled else { return }
    log(.debug, message)
  }

  func error(_ message: String) {
    log(.error, message)
  }

  private func prepareLogFile() {
    let directoryURL = logFileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: logFileURL.path) {
      FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }
  }

  private func log(_ level: LogLevel, _ message: String) {
    switch level {
    case .info:
      logger.info("\(message, privacy: .public)")
    case .debug:
      logger.debug("\(message, privacy: .public)")
    case .error:
      logger.error("\(message, privacy: .public)")
    }

    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(level.rawValue)] \(timestamp) \(message)\n"
    guard let data = line.data(using: .utf8),
      let fileHandle = try? FileHandle(forWritingTo: logFileURL)
    else { return }
    defer { try? fileHandle.close() }
    _ = try? fileHandle.seekToEnd()
    try? fileHandle.write(contentsOf: data)
  }
}
