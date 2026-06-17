import Foundation
import OSLog

enum LogLevel: String {
  case info = "INFO"
  case debug = "DEBUG"
  case error = "ERROR"
}

final class AppLogger {
  static let shared = AppLogger()

  private let maxLogFileSize = 1_000_000
  private let retainedLogFileCount = 3
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

  func clearLogFiles() throws {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: logFileURL)
    for index in 1...retainedLogFileCount {
      try? fileManager.removeItem(at: rotatedLogFileURL(index: index))
    }
    prepareLogFile()
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
    guard let data = line.data(using: .utf8) else { return }
    rotateLogsIfNeeded(appendingByteCount: data.count)
    guard let fileHandle = try? FileHandle(forWritingTo: logFileURL) else { return }
    defer { try? fileHandle.close() }
    _ = try? fileHandle.seekToEnd()
    try? fileHandle.write(contentsOf: data)
  }

  private func rotateLogsIfNeeded(appendingByteCount: Int) {
    let fileManager = FileManager.default
    let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path)
    let currentSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
    guard currentSize + appendingByteCount > maxLogFileSize else { return }

    for index in stride(from: retainedLogFileCount, through: 1, by: -1) {
      let sourceURL = index == 1 ? logFileURL : rotatedLogFileURL(index: index - 1)
      let destinationURL = rotatedLogFileURL(index: index)
      if fileManager.fileExists(atPath: destinationURL.path) {
        try? fileManager.removeItem(at: destinationURL)
      }
      if fileManager.fileExists(atPath: sourceURL.path) {
        try? fileManager.moveItem(at: sourceURL, to: destinationURL)
      }
    }
    prepareLogFile()
  }

  private func rotatedLogFileURL(index: Int) -> URL {
    logFileURL.deletingLastPathComponent()
      .appendingPathComponent("\(logFileURL.lastPathComponent).\(index)")
  }
}
