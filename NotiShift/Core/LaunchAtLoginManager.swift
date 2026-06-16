import AppKit
import Foundation
import ServiceManagement

final class LaunchAtLoginManager {
  private let logger = AppLogger.shared

  var isEnabled: Bool {
    if #available(macOS 13.0, *) {
      return SMAppService.mainApp.status == .enabled
    }
    return launchAgentExists
  }

  func setEnabled(_ enabled: Bool) throws {
    if #available(macOS 13.0, *) {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return
    }

    if enabled {
      try installLaunchAgent()
    } else {
      try removeLaunchAgent()
    }
  }

  private var launchAgentURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents/\(AppConstants.bundleIdentifier).plist")
  }

  private var launchAgentExists: Bool {
    FileManager.default.fileExists(atPath: launchAgentURL.path)
  }

  private func installLaunchAgent() throws {
    guard let executablePath = Bundle.main.executablePath else { return }
    let directoryURL = launchAgentURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(AppConstants.bundleIdentifier)</string>
      <key>ProgramArguments</key>
      <array>
        <string>\(executablePath)</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
    </dict>
    </plist>
    """
    try plist.write(to: launchAgentURL, atomically: true, encoding: .utf8)
    logger.info("Installed launch agent at \(launchAgentURL.path)")
  }

  private func removeLaunchAgent() throws {
    guard launchAgentExists else { return }
    try FileManager.default.removeItem(at: launchAgentURL)
    logger.info("Removed launch agent at \(launchAgentURL.path)")
  }
}
