import AppKit
import Foundation

enum LetsMove {
  private static let skipArgument = "--notishift-skip-move-to-applications"

  static func moveToApplicationsFolderIfNeeded() -> Bool {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
    guard !CommandLine.arguments.contains(skipArgument) else { return false }

    let currentURL = Bundle.main.bundleURL.standardizedFileURL
    guard !isInApplicationsFolder(currentURL) else { return false }

    let targetURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
      .appendingPathComponent(currentURL.lastPathComponent)
      .standardizedFileURL

    guard askUserToMoveApp() else {
      AppLogger.shared.info("User declined move to Applications")
      return false
    }

    do {
      try replaceExistingAppIfNeeded(at: targetURL)
      try FileManager.default.copyItem(at: currentURL, to: targetURL)
      AppLogger.shared.info("Moved app to \(targetURL.path)")
      try relaunchApp(at: targetURL)
      NSApp.terminate(nil)
      return true
    } catch {
      AppLogger.shared.error("Move to Applications failed: \(error.localizedDescription)")
      showMoveFailedAlert(error: error)
      return false
    }
  }

  private static func isInApplicationsFolder(_ url: URL) -> Bool {
    let appPath = url.standardizedFileURL.path
    let localApplicationsPath = "/Applications/"
    let userApplicationsPath = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Applications", isDirectory: true)
      .standardizedFileURL
      .path + "/"

    return appPath.hasPrefix(localApplicationsPath) || appPath.hasPrefix(userApplicationsPath)
  }

  private static func askUserToMoveApp() -> Bool {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = L10n.text("letsMove.title")
    alert.informativeText = L10n.text("letsMove.message")
    alert.addButton(withTitle: L10n.text("letsMove.moveButton"))
    alert.addButton(withTitle: L10n.text("letsMove.notNowButton"))
    return alert.runModal() == .alertFirstButtonReturn
  }

  private static func replaceExistingAppIfNeeded(at targetURL: URL) throws {
    guard FileManager.default.fileExists(atPath: targetURL.path) else { return }
    try FileManager.default.trashItem(at: targetURL, resultingItemURL: nil)
  }

  private static func relaunchApp(at url: URL) throws {
    let arguments = CommandLine.arguments
      .dropFirst()
      .filter { !$0.hasPrefix("-psn_") && $0 != skipArgument } + [skipArgument]

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-n", "-a", url.path, "--args"] + arguments
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      throw CocoaError(.executableLoad)
    }

    AppLogger.shared.info("Relaunched moved app from \(url.path)")
  }

  private static func showMoveFailedAlert(error: Error) {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = L10n.text("letsMove.errorTitle")
    alert.informativeText = String(format: L10n.text("letsMove.errorMessage"), error.localizedDescription)
    alert.addButton(withTitle: L10n.text("button.ok"))
    alert.runModal()
  }
}
