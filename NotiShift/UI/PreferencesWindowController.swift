import AppKit
import Foundation

protocol PreferencesWindowControllerDelegate: AnyObject {
  func preferencesDidSelectPosition()
  func preferencesDidRequestPermissionCheck()
  func preferencesDidRequestNotificationSettings()
  func preferencesDidRequestTestNotification()
  func preferencesDidRequestRestartWatcher()
  func preferencesDidChangeLanguage()
}

final class PreferencesWindowController: NSWindowController {
  weak var preferencesDelegate: PreferencesWindowControllerDelegate?

  private let preferences: NotiShiftPreferences
  private let permissionManager: AccessibilityPermissionManager
  private let launchAtLoginManager: LaunchAtLoginManager
  private let diagnosticsExporter: DiagnosticsExporter
  private let updateChecker: UpdateChecker
  private let logger = AppLogger.shared

  private let statusSummaryStack = NSStackView()
  private let enabledStatusLabel = NSTextField(labelWithString: "")
  private let permissionStatusSummaryLabel = NSTextField(labelWithString: "")
  private let positionStatusLabel = NSTextField(labelWithString: "")
  private let pauseStatusSummaryLabel = NSTextField(labelWithString: "")
  private let versionStatusLabel = NSTextField(labelWithString: "")
  private let tabView = NSTabView()
  private let launchAtLoginButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
  private let languagePopup = NSPopUpButton()
  private let automaticUpdatesButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
  private let positionPickerLabel = NSTextField(labelWithString: "")
  private var positionButtons: [NotificationPosition: NSButton] = [:]
  private let pauseStatusLabel = NSTextField(labelWithString: "")
  private let accessibilityStatusLabel = NSTextField(labelWithString: "")
  private let testNotificationResultLabel = NSTextField(wrappingLabelWithString: "")
  private let languageLabel = NSTextField(labelWithString: "")
  private let debugLoggingButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)

  init(
    preferences: NotiShiftPreferences,
    permissionManager: AccessibilityPermissionManager,
    launchAtLoginManager: LaunchAtLoginManager,
    diagnosticsExporter: DiagnosticsExporter,
    updateChecker: UpdateChecker
  ) {
    self.preferences = preferences
    self.permissionManager = permissionManager
    self.launchAtLoginManager = launchAtLoginManager
    self.diagnosticsExporter = diagnosticsExporter
    self.updateChecker = updateChecker

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = L10n.text("preferences.title")
    window.isReleasedWhenClosed = false
    super.init(window: window)

    window.contentView = makeContentView()
    refresh()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func showWindow(_ sender: Any?) {
    refresh()
    super.showWindow(sender)
    window?.center()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeContentView() -> NSView {
    let contentView = NSView()
    contentView.translatesAutoresizingMaskIntoConstraints = false

    statusSummaryStack.translatesAutoresizingMaskIntoConstraints = false
    statusSummaryStack.orientation = .vertical
    statusSummaryStack.alignment = .leading
    statusSummaryStack.spacing = 4
    statusSummaryStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    for label in [enabledStatusLabel, permissionStatusSummaryLabel, positionStatusLabel, pauseStatusSummaryLabel, versionStatusLabel] {
      label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
      label.textColor = .secondaryLabelColor
      statusSummaryStack.addArrangedSubview(label)
    }

    tabView.translatesAutoresizingMaskIntoConstraints = false
    tabView.addTabViewItem(makeTab(identifier: "general", label: L10n.text("preferences.general"), view: makeGeneralView()))
    tabView.addTabViewItem(makeTab(identifier: "permissions", label: L10n.text("preferences.permissions"), view: makePermissionsView()))
    tabView.addTabViewItem(makeTab(identifier: "advanced", label: L10n.text("preferences.advanced"), view: makeAdvancedView()))
    contentView.addSubview(statusSummaryStack)
    contentView.addSubview(tabView)

    NSLayoutConstraint.activate([
      statusSummaryStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      statusSummaryStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      statusSummaryStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
      tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      tabView.topAnchor.constraint(equalTo: statusSummaryStack.bottomAnchor, constant: 12),
      tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
    ])

    return contentView
  }

  private func makeTab(identifier: String, label: String, view: NSView) -> NSTabViewItem {
    let item = NSTabViewItem(identifier: identifier)
    item.label = label
    item.view = view
    return item
  }

  private func makeGeneralView() -> NSView {
    let view = NSView()
    let stack = makeStackView()

    launchAtLoginButton.target = self
    launchAtLoginButton.action = #selector(toggleLaunchAtLogin)

    let languageRow = NSStackView()
    languageRow.orientation = .horizontal
    languageRow.alignment = .centerY
    languageRow.spacing = 12

    languageLabel.widthAnchor.constraint(equalToConstant: 160).isActive = true
    languagePopup.target = self
    languagePopup.action = #selector(selectLanguage)
    rebuildLanguageMenu()
    languageRow.addArrangedSubview(languageLabel)
    languageRow.addArrangedSubview(languagePopup)

    automaticUpdatesButton.target = self
    automaticUpdatesButton.action = #selector(toggleAutomaticallyCheckForUpdates)
    let checkUpdatesButton = NSButton(title: L10n.text("preferences.checkForUpdatesNow"), target: self, action: #selector(checkForUpdatesNow))
    pauseStatusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    pauseStatusLabel.textColor = .secondaryLabelColor
    let pauseButton = NSButton(title: L10n.text("preferences.pauseForOneHour"), target: self, action: #selector(pauseForOneHour))
    let resumeButton = NSButton(title: L10n.text("preferences.resumeNow"), target: self, action: #selector(resumeNow))

    stack.addArrangedSubview(launchAtLoginButton)
    stack.addArrangedSubview(languageRow)
    stack.addArrangedSubview(positionPickerLabel)
    stack.addArrangedSubview(makePositionPicker())
    stack.addArrangedSubview(pauseStatusLabel)
    stack.addArrangedSubview(pauseButton)
    stack.addArrangedSubview(resumeButton)
    stack.addArrangedSubview(automaticUpdatesButton)
    stack.addArrangedSubview(checkUpdatesButton)
    pin(stack, to: view)
    return view
  }

  private func makePermissionsView() -> NSView {
    let view = NSView()
    let stack = makeStackView()

    accessibilityStatusLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    testNotificationResultLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    testNotificationResultLabel.textColor = .secondaryLabelColor
    testNotificationResultLabel.maximumNumberOfLines = 0
    testNotificationResultLabel.preferredMaxLayoutWidth = 420

    let openAccessibilityButton = NSButton(title: L10n.text("preferences.openAccessibilitySettings"), target: self, action: #selector(openAccessibilitySettings))
    let openNotificationButton = NSButton(title: L10n.text("preferences.openNotificationSettings"), target: self, action: #selector(openNotificationSettings))
    let retryButton = NSButton(title: L10n.text("preferences.retryPermissionCheck"), target: self, action: #selector(retryPermissionCheck))
    let testButton = NSButton(title: L10n.text("preferences.sendTestNotification"), target: self, action: #selector(sendTestNotification))

    stack.addArrangedSubview(accessibilityStatusLabel)
    stack.addArrangedSubview(openAccessibilityButton)
    stack.addArrangedSubview(openNotificationButton)
    stack.addArrangedSubview(retryButton)
    stack.addArrangedSubview(testButton)
    stack.addArrangedSubview(testNotificationResultLabel)
    pin(stack, to: view)
    return view
  }

  private func makeAdvancedView() -> NSView {
    let view = NSView()
    let stack = makeStackView()

    debugLoggingButton.target = self
    debugLoggingButton.action = #selector(toggleDebugLogging)
    let restartButton = NSButton(title: L10n.text("preferences.restartWatcher"), target: self, action: #selector(restartWatcher))
    let logButton = NSButton(title: L10n.text("preferences.openLogFile"), target: self, action: #selector(openLogFile))
    let copySummaryButton = NSButton(title: L10n.text("preferences.copyDiagnosticsSummary"), target: self, action: #selector(copyDiagnosticsSummary))
    let diagnosticsButton = NSButton(title: L10n.text("preferences.exportDiagnostics"), target: self, action: #selector(exportDiagnostics))

    stack.addArrangedSubview(debugLoggingButton)
    stack.addArrangedSubview(restartButton)
    stack.addArrangedSubview(logButton)
    stack.addArrangedSubview(copySummaryButton)
    stack.addArrangedSubview(diagnosticsButton)
    pin(stack, to: view)
    return view
  }

  private func makePositionPicker() -> NSGridView {
    let rows: [[NotificationPosition]] = [
      [.topLeft, .topCenter, .topRight],
      [.middleLeft, .center, .middleRight],
      [.bottomLeft, .bottomCenter, .bottomRight],
    ]
    let buttons = rows.map { row in
      row.map { position in
        let button = NSButton(title: position.displayName, target: self, action: #selector(selectPositionFromPicker(_:)))
        button.bezelStyle = .texturedRounded
        button.setButtonType(.toggle)
        button.tag = NotificationPosition.allCases.firstIndex(of: position) ?? 0
        button.widthAnchor.constraint(equalToConstant: 120).isActive = true
        positionButtons[position] = button
        return button
      }
    }

    let grid = NSGridView(views: buttons)
    grid.rowSpacing = 6
    grid.columnSpacing = 6
    return grid
  }

  private func makeStackView() -> NSStackView {
    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    return stack
  }

  private func pin(_ stack: NSStackView, to view: NSView) {
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: view.topAnchor),
    ])
  }

  private func refresh() {
    window?.title = L10n.text("preferences.title")
    tabView.tabViewItem(at: 0).label = L10n.text("preferences.general")
    tabView.tabViewItem(at: 1).label = L10n.text("preferences.permissions")
    tabView.tabViewItem(at: 2).label = L10n.text("preferences.advanced")
    launchAtLoginButton.title = L10n.text("preferences.launchAtLogin")
    languageLabel.stringValue = L10n.text("preferences.language")
    positionPickerLabel.stringValue = L10n.text("preferences.positionPicker")
    automaticUpdatesButton.title = L10n.text("preferences.automaticallyCheckForUpdates")
    debugLoggingButton.title = L10n.text("preferences.debugLogging")
    refreshPauseStatus()
    rebuildLanguageMenu()
    refreshStatusSummary()

    launchAtLoginButton.state = launchAtLoginManager.isEnabled ? .on : .off
    automaticUpdatesButton.state = preferences.automaticallyCheckForUpdates ? .on : .off
    debugLoggingButton.state = preferences.debugLoggingEnabled ? .on : .off
    accessibilityStatusLabel.stringValue = permissionManager.isTrusted
      ? L10n.text("preferences.accessibilityGranted")
      : L10n.text("preferences.accessibilityRequired")
    testNotificationResultLabel.stringValue = preferences.lastTestNotificationResult.map {
      String(format: L10n.text("preferences.lastTestResult"), $0)
    } ?? L10n.text("preferences.lastTestResultNone")

    if let index = AppLanguage.allCases.firstIndex(of: preferences.selectedLanguage) {
      languagePopup.selectItem(at: index)
    }
    refreshPositionPicker()
  }

  private func refreshPositionPicker() {
    for (position, button) in positionButtons {
      button.title = position.displayName
      button.state = preferences.selectedPosition == position ? .on : .off
    }
  }

  private func refreshPauseStatus() {
    if let pauseUntil = preferences.pauseUntil, pauseUntil > Date() {
      pauseStatusLabel.stringValue = String(
        format: L10n.text("preferences.pauseUntil"),
        DateFormatter.localizedString(from: pauseUntil, dateStyle: .none, timeStyle: .short)
      )
    } else {
      preferences.pauseUntil = nil
      pauseStatusLabel.stringValue = L10n.text("preferences.notPaused")
    }
  }

  private func refreshStatusSummary() {
    enabledStatusLabel.stringValue = String(
      format: L10n.text("status.enabled"),
      preferences.isEnabled ? L10n.text("status.on") : L10n.text("status.off")
    )
    permissionStatusSummaryLabel.stringValue = String(
      format: L10n.text("status.accessibility"),
      permissionManager.isTrusted ? L10n.text("status.granted") : L10n.text("status.required")
    )
    positionStatusLabel.stringValue = String(
      format: L10n.text("status.position"),
      preferences.selectedPosition.displayName
    )
    pauseStatusSummaryLabel.stringValue = String(
      format: L10n.text("status.pause"),
      pauseStatusText()
    )
    versionStatusLabel.stringValue = String(
      format: L10n.text("status.version"),
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.text("status.unknown")
    )
  }

  private func rebuildLanguageMenu() {
    languagePopup.removeAllItems()
    for language in AppLanguage.allCases {
      languagePopup.addItem(withTitle: language.displayName)
      languagePopup.lastItem?.representedObject = language.rawValue
    }
  }

  @objc private func toggleLaunchAtLogin() {
    do {
      try launchAtLoginManager.setEnabled(launchAtLoginButton.state == .on)
    } catch {
      showAlert(title: L10n.text("alert.launchAtLoginError"), message: error.localizedDescription)
    }
    refresh()
  }

  @objc private func selectLanguage() {
    guard
      let rawValue = languagePopup.selectedItem?.representedObject as? String,
      let language = AppLanguage(rawValue: rawValue)
    else {
      return
    }
    preferences.selectedLanguage = language
    preferencesDelegate?.preferencesDidChangeLanguage()
    refresh()
  }

  @objc private func toggleAutomaticallyCheckForUpdates() {
    preferences.automaticallyCheckForUpdates = automaticUpdatesButton.state == .on
  }

  @objc private func pauseForOneHour() {
    preferences.pauseUntil = Date().addingTimeInterval(60 * 60)
    refresh()
  }

  @objc private func resumeNow() {
    preferences.pauseUntil = nil
    refresh()
  }

  @objc private func selectPositionFromPicker(_ sender: NSButton) {
    guard NotificationPosition.allCases.indices.contains(sender.tag) else {
      return
    }
    let position = NotificationPosition.allCases[sender.tag]
    preferences.selectedPosition = position
    preferencesDelegate?.preferencesDidSelectPosition()
    refresh()
  }

  @objc private func checkForUpdatesNow() {
    Task { @MainActor in
      await showUpdateCheckResult(showUpToDate: true)
    }
  }

  @MainActor
  func showUpdateCheckResult(showUpToDate: Bool) async {
    do {
      preferences.lastUpdateCheckAt = Date()
      let result = try await updateChecker.check()
      switch result {
      case let .upToDate(currentVersion):
        guard showUpToDate else { return }
        showAlert(
          title: L10n.text("update.upToDateTitle"),
          message: String(format: L10n.text("update.upToDateMessage"), currentVersion)
        )
      case let .updateAvailable(currentVersion, release):
        showUpdateAvailableAlert(currentVersion: currentVersion, release: release)
      }
    } catch {
      guard showUpToDate else { return }
      showAlert(title: L10n.text("update.errorTitle"), message: error.localizedDescription)
    }
  }

  @objc private func openAccessibilitySettings() {
    permissionManager.openAccessibilitySettings()
  }

  @objc private func openNotificationSettings() {
    preferencesDelegate?.preferencesDidRequestNotificationSettings()
  }

  @objc private func retryPermissionCheck() {
    preferencesDelegate?.preferencesDidRequestPermissionCheck()
    refresh()
  }

  @objc private func sendTestNotification() {
    preferencesDelegate?.preferencesDidRequestTestNotification()
  }

  @objc private func toggleDebugLogging() {
    preferences.debugLoggingEnabled = debugLoggingButton.state == .on
  }

  @objc private func restartWatcher() {
    preferencesDelegate?.preferencesDidRequestRestartWatcher()
  }

  @objc private func openLogFile() {
    NSWorkspace.shared.open(logger.logFileURL)
  }

  @objc private func copyDiagnosticsSummary() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(diagnosticsSummary(), forType: .string)
    showAlert(title: L10n.text("diagnosticsSummary.copiedTitle"), message: L10n.text("diagnosticsSummary.copiedMessage"))
  }

  @objc private func exportDiagnostics() {
    do {
      let url = try diagnosticsExporter.export()
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      showAlert(title: L10n.text("alert.diagnosticsError"), message: error.localizedDescription)
    }
  }

  private func diagnosticsSummary() -> String {
    let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.text("status.unknown")
    let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? L10n.text("status.unknown")
    let enabled = preferences.isEnabled ? L10n.text("status.on") : L10n.text("status.off")
    let accessibility = permissionManager.isTrusted ? L10n.text("status.granted") : L10n.text("status.required")
    let automaticUpdates = preferences.automaticallyCheckForUpdates ? L10n.text("status.on") : L10n.text("status.off")
    let debugLogging = preferences.debugLoggingEnabled ? L10n.text("status.on") : L10n.text("status.off")
    let pause = pauseStatusText()
    let lastTest = preferences.lastTestNotificationResult ?? L10n.text("preferences.lastTestResultNone")

    return """
    NotiShift Diagnostics Summary
    App Version: \(appVersion)
    Build: \(buildVersion)
    macOS: \(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)
    Enabled: \(enabled)
    Accessibility: \(accessibility)
    Position: \(preferences.selectedPosition.displayName)
    Pause: \(pause)
    Automatically Check for Updates: \(automaticUpdates)
    Debug Logging: \(debugLogging)
    Last Test: \(lastTest)
    """
  }

  private func pauseStatusText() -> String {
    if let pauseUntil = preferences.pauseUntil, pauseUntil > Date() {
      return String(
        format: L10n.text("preferences.pauseUntil"),
        DateFormatter.localizedString(from: pauseUntil, dateStyle: .none, timeStyle: .short)
      )
    }
    return L10n.text("preferences.notPaused")
  }

  private func showAlert(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: L10n.text("button.ok"))
    alert.runModal()
  }

  private func showUpdateAvailableAlert(currentVersion: String, release: ReleaseInfo) {
    let alert = NSAlert()
    alert.messageText = String(format: L10n.text("update.availableTitle"), release.version)
    var message = String(
      format: L10n.text("update.availableMessage"),
      currentVersion,
      release.version
    )
    if let notes = release.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      message += "\n\n\(notes)"
    }
    alert.informativeText = message
    alert.addButton(withTitle: L10n.text("update.openRelease"))
    alert.addButton(withTitle: L10n.text("button.ok"))

    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(release.url)
    }
  }
}
