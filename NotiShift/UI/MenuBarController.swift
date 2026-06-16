import AppKit
import Foundation

protocol MenuBarControllerDelegate: AnyObject {
  func menuBarControllerDidToggleEnabled()
  func menuBarControllerDidSelectPosition()
  func menuBarControllerDidRequestTestNotification()
  func menuBarControllerDidRequestNotificationSettings()
  func menuBarControllerDidRequestPermissionCheck()
  func menuBarControllerDidRequestRestartWatcher()
}

final class MenuBarController {
  weak var delegate: MenuBarControllerDelegate?

  private let preferences: NotiShiftPreferences
  private let permissionManager: AccessibilityPermissionManager
  private let launchAtLoginManager: LaunchAtLoginManager
  private let diagnosticsExporter: DiagnosticsExporter
  private let logger = AppLogger.shared
  private var statusItem: NSStatusItem?

  init(
    preferences: NotiShiftPreferences,
    permissionManager: AccessibilityPermissionManager,
    launchAtLoginManager: LaunchAtLoginManager,
    diagnosticsExporter: DiagnosticsExporter
  ) {
    self.preferences = preferences
    self.permissionManager = permissionManager
    self.launchAtLoginManager = launchAtLoginManager
    self.diagnosticsExporter = diagnosticsExporter
  }

  func install() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem?.button {
      button.image = menuBarImage()
      button.imagePosition = .imageOnly
    }
    rebuildMenu()
  }

  private func menuBarImage() -> NSImage {
    if #available(macOS 11.0, *),
      let image = NSImage(systemSymbolName: "bell", accessibilityDescription: "NotiShift")
    {
      image.isTemplate = true
      image.size = NSSize(width: 18, height: 18)
      return image
    }

    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    NSColor.black.setStroke()
    NSColor.black.setFill()

    let bell = NSBezierPath()
    bell.lineWidth = 1.7
    bell.move(to: NSPoint(x: 5.0, y: 6.4))
    bell.curve(
      to: NSPoint(x: 13.0, y: 6.4),
      controlPoint1: NSPoint(x: 5.1, y: 11.4),
      controlPoint2: NSPoint(x: 12.9, y: 11.4)
    )
    bell.line(to: NSPoint(x: 14.2, y: 5.0))
    bell.line(to: NSPoint(x: 3.8, y: 5.0))
    bell.close()
    bell.stroke()

    NSBezierPath(ovalIn: NSRect(x: 7.2, y: 2.3, width: 3.6, height: 3.0)).fill()
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  func rebuildMenu() {
    let menu = NSMenu()

    let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
    enabledItem.target = self
    enabledItem.state = preferences.isEnabled ? .on : .off
    menu.addItem(enabledItem)

    let testItem = NSMenuItem(title: "Send System Notification", action: #selector(sendTestNotification), keyEquivalent: "t")
    testItem.target = self
    menu.addItem(testItem)

    menu.addItem(.separator())

    let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
    let positionMenu = NSMenu()
    for position in NotificationPosition.allCases {
      let item = NSMenuItem(title: position.displayName, action: #selector(selectPosition(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = position
      item.state = preferences.selectedPosition == position ? .on : .off
      positionMenu.addItem(item)
    }
    positionItem.submenu = positionMenu
    menu.addItem(positionItem)

    let permissionsItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
    permissionsItem.submenu = buildPermissionsMenu()
    menu.addItem(permissionsItem)

    let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
    settingsItem.submenu = buildSettingsMenu()
    menu.addItem(settingsItem)

    let diagnosticsItem = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
    diagnosticsItem.submenu = buildDiagnosticsMenu()
    menu.addItem(diagnosticsItem)

    menu.addItem(.separator())
    let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
    aboutItem.target = self
    menu.addItem(aboutItem)

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem?.menu = menu
  }

  private func buildPermissionsMenu() -> NSMenu {
    let menu = NSMenu()

    if permissionManager.isTrusted {
      let permissionItem = NSMenuItem(title: "Accessibility Permission: Granted", action: nil, keyEquivalent: "")
      permissionItem.isEnabled = false
      menu.addItem(permissionItem)
    } else {
      let permissionItem = NSMenuItem(
        title: "Accessibility Permission Required",
        action: #selector(openAccessibilitySettings),
        keyEquivalent: ""
      )
      permissionItem.target = self
      menu.addItem(permissionItem)

      let settingsItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
      settingsItem.target = self
      menu.addItem(settingsItem)

      let retryItem = NSMenuItem(title: "Retry Permission Check", action: #selector(retryPermission), keyEquivalent: "")
      retryItem.target = self
      menu.addItem(retryItem)
    }

    menu.addItem(.separator())

    let notificationItem = NSMenuItem(title: "Open Notification Settings", action: #selector(openNotificationSettings), keyEquivalent: "")
    notificationItem.target = self
    menu.addItem(notificationItem)

    return menu
  }

  private func buildSettingsMenu() -> NSMenu {
    let menu = NSMenu()

    let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
    loginItem.target = self
    loginItem.state = launchAtLoginManager.isEnabled ? .on : .off
    menu.addItem(loginItem)

    return menu
  }

  private func buildDiagnosticsMenu() -> NSMenu {
    let menu = NSMenu()

    let debugItem = NSMenuItem(title: "Debug Logging", action: #selector(toggleDebugLogging(_:)), keyEquivalent: "")
    debugItem.target = self
    debugItem.state = preferences.debugLoggingEnabled ? .on : .off
    menu.addItem(debugItem)

    let restartItem = NSMenuItem(title: "Restart Watcher", action: #selector(restartWatcher), keyEquivalent: "")
    restartItem.target = self
    menu.addItem(restartItem)

    let logItem = NSMenuItem(title: "Open Log File", action: #selector(openLogFile), keyEquivalent: "")
    logItem.target = self
    menu.addItem(logItem)

    let diagnosticsItem = NSMenuItem(title: "Export Diagnostics", action: #selector(exportDiagnostics), keyEquivalent: "")
    diagnosticsItem.target = self
    menu.addItem(diagnosticsItem)

    return menu
  }

  @objc private func openAccessibilitySettings() {
    permissionManager.openAccessibilitySettings()
  }

  @objc private func retryPermission() {
    delegate?.menuBarControllerDidRequestPermissionCheck()
    rebuildMenu()
  }

  @objc private func toggleEnabled(_ sender: NSMenuItem) {
    preferences.isEnabled.toggle()
    sender.state = preferences.isEnabled ? .on : .off
    delegate?.menuBarControllerDidToggleEnabled()
    rebuildMenu()
  }

  @objc private func selectPosition(_ sender: NSMenuItem) {
    guard let position = sender.representedObject as? NotificationPosition else { return }
    preferences.selectedPosition = position
    delegate?.menuBarControllerDidSelectPosition()
    rebuildMenu()
  }

  @objc private func sendTestNotification() {
    delegate?.menuBarControllerDidRequestTestNotification()
  }

  @objc private func openNotificationSettings() {
    delegate?.menuBarControllerDidRequestNotificationSettings()
  }

  @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
    do {
      try launchAtLoginManager.setEnabled(!launchAtLoginManager.isEnabled)
      rebuildMenu()
    } catch {
      showAlert(title: "Launch at Login Error", message: error.localizedDescription)
    }
  }

  @objc private func toggleDebugLogging(_ sender: NSMenuItem) {
    preferences.debugLoggingEnabled.toggle()
    sender.state = preferences.debugLoggingEnabled ? .on : .off
    rebuildMenu()
  }

  @objc private func restartWatcher() {
    delegate?.menuBarControllerDidRequestRestartWatcher()
  }

  @objc private func openLogFile() {
    NSWorkspace.shared.open(logger.logFileURL)
  }

  @objc private func exportDiagnostics() {
    do {
      let url = try diagnosticsExporter.export()
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      showAlert(title: "Diagnostics Error", message: error.localizedDescription)
    }
  }

  @objc private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
