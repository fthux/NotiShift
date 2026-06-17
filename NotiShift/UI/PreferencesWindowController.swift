import AppKit
import Foundation

protocol PreferencesWindowControllerDelegate: AnyObject {
  func preferencesDidSelectPosition()
  func preferencesDidRequestPermissionCheck() -> Bool
  func preferencesDidRequestNotificationPermissionStatus(completion: @escaping (NotificationPermissionStatus) -> Void)
  func preferencesDidRequestNotificationSettings() -> Bool
  func preferencesDidRequestTestNotification(completion: @escaping (TestNotificationResult) -> Void)
  func preferencesDidRequestRestartWatcher() -> Bool
  func preferencesDidChangeLanguage()
}

final class PreferencesWindowController: NSWindowController, NSTabViewDelegate, NSWindowDelegate {
  private struct ActionStatus {
    let key: String
    let argument: String?
    let isError: Bool
  }

  weak var preferencesDelegate: PreferencesWindowControllerDelegate?

  private let preferences: NotiShiftPreferences
  private let permissionManager: AccessibilityPermissionManager
  private let launchAtLoginManager: LaunchAtLoginManager
  private let diagnosticsExporter: DiagnosticsExporter
  private let updateChecker: UpdateChecker
  private let logger = AppLogger.shared

  private let tabView = NSTabView()
  private let launchAtLoginButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
  private let languagePopup = NSPopUpButton()
  private let automaticUpdatesButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
  private let positionPickerLabel = NSTextField(labelWithString: "")
  private var positionButtons: [NotificationPosition: NSButton] = [:]
  private let accessibilityStatusLabel = NSTextField(labelWithString: "")
  private let notificationStatusLabel = NSTextField(labelWithString: "")
  private let testNotificationResultLabel = NSTextField(wrappingLabelWithString: "")
  private let permissionsActionStatusLabel = NSTextField(wrappingLabelWithString: "")
  private let advancedActionStatusLabel = NSTextField(wrappingLabelWithString: "")
  private let languageLabel = NSTextField(labelWithString: "")
  private let debugLoggingButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
  private var localizedButtons: [(button: NSButton, titleKey: String)] = []
  private var localizedLabels: [(label: NSTextField, textKey: String)] = []
  private var notificationPermissionStatus: NotificationPermissionStatus?
  private var notificationPermissionRequestID = 0
  private var actionStatuses: [ObjectIdentifier: ActionStatus] = [:]
  private var actionStatusHideWorkItems: [ObjectIdentifier: DispatchWorkItem] = [:]
  private var permissionRefreshTimer: Timer?

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
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = L10n.text("preferences.title")
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self

    window.contentView = makeContentView()
    refresh()
    DispatchQueue.main.async { [weak self] in
      self?.resizeWindowForSelectedTab(animated: false)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func showWindow(_ sender: Any?) {
    refresh()
    super.showWindow(sender)
    startPermissionRefreshTimer()
    resizeWindowForSelectedTab(animated: false)
    window?.center()
    NSApp.activate(ignoringOtherApps: true)
  }

  override func close() {
    stopPermissionRefreshTimer()
    super.close()
  }

  func windowWillClose(_ notification: Notification) {
    stopPermissionRefreshTimer()
  }

  private func makeContentView() -> NSView {
    let contentView = NSView()
    contentView.translatesAutoresizingMaskIntoConstraints = false

    tabView.translatesAutoresizingMaskIntoConstraints = false
    tabView.delegate = self
    tabView.addTabViewItem(makeTab(identifier: "general", label: L10n.text("preferences.general"), symbolName: "gearshape", view: makeGeneralView()))
    tabView.addTabViewItem(makeTab(identifier: "permissions", label: L10n.text("preferences.permissions"), symbolName: "lock.shield", view: makePermissionsView()))
    tabView.addTabViewItem(makeTab(identifier: "advanced", label: L10n.text("preferences.advanced"), symbolName: "wrench.and.screwdriver", view: makeAdvancedView()))
    contentView.addSubview(tabView)

    NSLayoutConstraint.activate([
      tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
      tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
    ])

    return contentView
  }

  private func makeTab(identifier: String, label: String, symbolName: String, view: NSView) -> NSTabViewItem {
    let item = NSTabViewItem(identifier: identifier)
    item.label = label
    item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
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

    languagePopup.target = self
    languagePopup.action = #selector(selectLanguage)
    rebuildLanguageMenu()
    languageRow.addArrangedSubview(languageLabel)
    languageRow.addArrangedSubview(languagePopup)

    automaticUpdatesButton.target = self
    automaticUpdatesButton.action = #selector(toggleAutomaticallyCheckForUpdates)
    let checkUpdatesButton = makeLocalizedButton(titleKey: "preferences.checkForUpdatesNow", action: #selector(checkForUpdatesNow))

    stack.addArrangedSubview(makeGroup([
      launchAtLoginButton,
      automaticUpdatesButton,
      checkUpdatesButton,
    ]))
    stack.addArrangedSubview(makeSeparator())
    stack.addArrangedSubview(makeGroup([
      languageRow,
    ]))
    stack.addArrangedSubview(makeSeparator())
    stack.addArrangedSubview(makeGroup([
      positionPickerLabel,
      makePositionPicker(),
    ]))
    pin(stack, to: view)
    return view
  }

  private func makePermissionsView() -> NSView {
    let view = NSView()
    let stack = makeStackView()

    accessibilityStatusLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    notificationStatusLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    testNotificationResultLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    testNotificationResultLabel.textColor = .secondaryLabelColor
    testNotificationResultLabel.maximumNumberOfLines = 0
    testNotificationResultLabel.preferredMaxLayoutWidth = 420
    configureStatusLabel(permissionsActionStatusLabel)

    stack.addArrangedSubview(makeGroup([
      accessibilityStatusLabel,
      makeActionRow(titleKey: "preferences.openAccessibilitySettings", symbolName: "accessibility", action: #selector(openAccessibilitySettings)),
      makeActionRow(titleKey: "preferences.retryPermissionCheck", symbolName: "arrow.clockwise", action: #selector(retryPermissionCheck), showsChevron: false),
    ]))
    stack.addArrangedSubview(makeSeparator())
    stack.addArrangedSubview(makeGroup([
      notificationStatusLabel,
      makeActionRow(titleKey: "preferences.openNotificationSettings", symbolName: "bell.badge", action: #selector(openNotificationSettings)),
      makeActionRow(titleKey: "preferences.sendTestNotification", symbolName: "paperplane", action: #selector(sendTestNotification), showsChevron: false),
      testNotificationResultLabel,
      permissionsActionStatusLabel,
    ]))
    pin(stack, to: view)
    return view
  }

  private func makeAdvancedView() -> NSView {
    let view = NSView()
    let stack = makeStackView()

    debugLoggingButton.target = self
    debugLoggingButton.action = #selector(toggleDebugLogging)
    configureStatusLabel(advancedActionStatusLabel)
    stack.addArrangedSubview(makeGroup([
      debugLoggingButton,
      makeActionRow(titleKey: "preferences.restartWatcher", symbolName: "arrow.triangle.2.circlepath", action: #selector(restartWatcher), showsChevron: false),
    ]))
    stack.addArrangedSubview(makeSeparator())
    stack.addArrangedSubview(makeGroup([
      makeActionRow(titleKey: "preferences.openLogFile", symbolName: "doc.text.magnifyingglass", action: #selector(openLogFile)),
      makeActionRow(titleKey: "preferences.copyDiagnosticsSummary", symbolName: "doc.on.doc", action: #selector(copyDiagnosticsSummary), showsChevron: false),
      makeActionRow(titleKey: "preferences.exportDiagnostics", symbolName: "square.and.arrow.up", action: #selector(exportDiagnostics), showsChevron: false),
      advancedActionStatusLabel,
    ]))
    pin(stack, to: view)
    return view
  }

  private func makeGroup(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    return stack
  }

  private func makeSeparator() -> NSBox {
    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    separator.widthAnchor.constraint(equalToConstant: 420).isActive = true
    return separator
  }

  private func makeLocalizedButton(titleKey: String, action: Selector) -> NSButton {
    let button = NSButton(title: L10n.text(titleKey), target: self, action: action)
    localizedButtons.append((button, titleKey))
    return button
  }

  private func makeActionRow(titleKey: String, symbolName: String, action: Selector, showsChevron: Bool = true) -> NSView {
    let title = L10n.text(titleKey)
    let row = NSButton(title: "", target: self, action: action)
    row.bezelStyle = .regularSquare
    row.isBordered = false
    row.setButtonType(.momentaryChange)
    row.contentTintColor = .labelColor

    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false

    let icon = NSImageView()
    icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
    icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    icon.contentTintColor = .secondaryLabelColor
    icon.widthAnchor.constraint(equalToConstant: 18).isActive = true

    let label = NSTextField(labelWithString: title)
    label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    localizedLabels.append((label, titleKey))

    let spacer = NSView()
    let chevron = NSImageView()
    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    chevron.contentTintColor = .tertiaryLabelColor
    chevron.widthAnchor.constraint(equalToConstant: 12).isActive = true

    stack.addArrangedSubview(icon)
    stack.addArrangedSubview(label)
    stack.addArrangedSubview(spacer)
    if showsChevron {
      stack.addArrangedSubview(chevron)
    }
    row.addSubview(stack)

    NSLayoutConstraint.activate([
      row.heightAnchor.constraint(equalToConstant: 30),
      row.widthAnchor.constraint(equalToConstant: 420),
      stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
    ])

    return row
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
      stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
    ])
  }

  private func configureStatusLabel(_ label: NSTextField) {
    label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .secondaryLabelColor
    label.maximumNumberOfLines = 0
    label.preferredMaxLayoutWidth = 420
    label.stringValue = ""
    label.isHidden = true
  }

  private func setActionStatusText(_ text: String, label: NSTextField, isError: Bool) {
    label.stringValue = text
    label.isHidden = text.isEmpty
    label.textColor = isError ? .systemRed : .secondaryLabelColor
  }

  private func setActionStatus(_ key: String, argument: String? = nil, label: NSTextField, isError: Bool = false) {
    let text: String
    if let argument {
      text = String(format: L10n.text(key), argument)
    } else {
      text = L10n.text(key)
    }

    actionStatuses[ObjectIdentifier(label)] = ActionStatus(key: key, argument: argument, isError: isError)
    setActionStatusText(text, label: label, isError: isError)
    resizeWindowForSelectedTab(animated: true)
    scheduleActionStatusHide(label)
  }

  private func scheduleActionStatusHide(_ label: NSTextField) {
    let identifier = ObjectIdentifier(label)
    actionStatusHideWorkItems[identifier]?.cancel()

    let workItem = DispatchWorkItem { [weak self, weak label] in
      guard let self, let label else { return }
      self.setActionStatusText("", label: label, isError: false)
      let identifier = ObjectIdentifier(label)
      self.actionStatuses[identifier] = nil
      self.actionStatusHideWorkItems[identifier] = nil
      if label === self.permissionsActionStatusLabel || label === self.advancedActionStatusLabel {
        self.resizeWindowForSelectedTab(animated: true)
      }
    }

    actionStatusHideWorkItems[identifier] = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
  }

  private func resizeWindowForSelectedTab(animated: Bool) {
    guard
      let window,
      let contentView = window.contentView,
      let selectedView = tabView.selectedTabViewItem?.view
    else {
      return
    }

    contentView.layoutSubtreeIfNeeded()
    selectedView.layoutSubtreeIfNeeded()

    let contentInsets: CGFloat = 32
    let tabFrameExtraHeight = tabView.frame.height - tabView.contentRect.height
    let targetContentHeight = max(240, selectedView.fittingSize.height + tabFrameExtraHeight + contentInsets)
    let currentContentHeight = contentView.bounds.height
    let heightDelta = targetContentHeight - currentContentHeight
    guard abs(heightDelta) > 0.5 else { return }

    var frame = window.frame
    frame.origin.y -= heightDelta
    frame.size.height += heightDelta
    window.setFrame(frame, display: true, animate: animated)
  }

  func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    resizeWindowForSelectedTab(animated: true)
  }

  private func refresh() {
    window?.title = L10n.text("preferences.title")
    tabView.tabViewItem(at: 0).label = L10n.text("preferences.general")
    tabView.tabViewItem(at: 1).label = L10n.text("preferences.permissions")
    tabView.tabViewItem(at: 2).label = L10n.text("preferences.advanced")
    tabView.tabViewItem(at: 0).image?.accessibilityDescription = L10n.text("preferences.general")
    tabView.tabViewItem(at: 1).image?.accessibilityDescription = L10n.text("preferences.permissions")
    tabView.tabViewItem(at: 2).image?.accessibilityDescription = L10n.text("preferences.advanced")
    launchAtLoginButton.title = L10n.text("preferences.launchAtLogin")
    languageLabel.stringValue = L10n.text("preferences.language")
    positionPickerLabel.stringValue = L10n.text("preferences.positionPicker")
    automaticUpdatesButton.title = L10n.text("preferences.automaticallyCheckForUpdates")
    debugLoggingButton.title = L10n.text("preferences.debugLogging")
    refreshRegisteredLocalizedViews()
    refreshNotificationStatusLabel()
    rebuildLanguageMenu()

    launchAtLoginButton.state = launchAtLoginManager.isEnabled ? .on : .off
    automaticUpdatesButton.state = preferences.automaticallyCheckForUpdates ? .on : .off
    debugLoggingButton.state = preferences.debugLoggingEnabled ? .on : .off
    refreshPermissionStatuses()
    testNotificationResultLabel.stringValue = preferences.lastTestNotificationResult.map {
      String(format: L10n.text("preferences.lastTestResult"), $0)
    } ?? L10n.text("preferences.lastTestResultNone")

    if let index = AppLanguage.allCases.firstIndex(of: preferences.selectedLanguage) {
      languagePopup.selectItem(at: index)
    }
    refreshPositionPicker()
    resizeWindowForSelectedTab(animated: true)
  }

  private func refreshRegisteredLocalizedViews() {
    for item in localizedButtons {
      item.button.title = L10n.text(item.titleKey)
    }
    for item in localizedLabels {
      item.label.stringValue = L10n.text(item.textKey)
    }
    refreshVisibleActionStatuses()
  }

  private func refreshVisibleActionStatuses() {
    for (identifier, status) in actionStatuses {
      let label: NSTextField
      if identifier == ObjectIdentifier(permissionsActionStatusLabel) {
        label = permissionsActionStatusLabel
      } else if identifier == ObjectIdentifier(advancedActionStatusLabel) {
        label = advancedActionStatusLabel
      } else {
        continue
      }

      let text: String
      if let argument = status.argument {
        text = String(format: L10n.text(status.key), argument)
      } else {
        text = L10n.text(status.key)
      }
      setActionStatusText(text, label: label, isError: status.isError)
    }
  }

  private func refreshPositionPicker() {
    for (position, button) in positionButtons {
      button.title = position.displayName
      button.state = preferences.selectedPosition == position ? .on : .off
    }
  }

  private func refreshNotificationStatusLabel() {
    let key: String
    switch notificationPermissionStatus {
    case .granted:
      key = "preferences.notificationGranted"
    case .denied:
      key = "preferences.notificationDenied"
    case .notDetermined:
      key = "preferences.notificationNotDetermined"
    case nil:
      key = "preferences.notificationChecking"
    }
    notificationStatusLabel.stringValue = L10n.text(key)
  }

  private func refreshPermissionStatuses() {
    accessibilityStatusLabel.stringValue = permissionManager.isTrusted
      ? L10n.text("preferences.accessibilityGranted")
      : L10n.text("preferences.accessibilityRequired")
    requestNotificationPermissionStatus()
  }

  private func requestNotificationPermissionStatus() {
    notificationPermissionRequestID += 1
    let requestID = notificationPermissionRequestID
    preferencesDelegate?.preferencesDidRequestNotificationPermissionStatus { [weak self] status in
      DispatchQueue.main.async {
        guard let self else { return }
        guard requestID == self.notificationPermissionRequestID else { return }
        self.notificationPermissionStatus = status
        self.refreshNotificationStatusLabel()
        self.resizeWindowForSelectedTab(animated: true)
      }
    }
  }

  private func startPermissionRefreshTimer() {
    guard permissionRefreshTimer == nil else { return }
    refreshPermissionStatuses()
    permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.refreshPermissionStatuses()
    }
    if let permissionRefreshTimer {
      RunLoop.current.add(permissionRefreshTimer, forMode: .common)
    }
  }

  private func stopPermissionRefreshTimer() {
    permissionRefreshTimer?.invalidate()
    permissionRefreshTimer = nil
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
    let didOpen = permissionManager.openAccessibilitySettings()
    setActionStatus(
      didOpen ? "preferences.actionOpenedAccessibilitySettings" : "preferences.actionOpenAccessibilitySettingsFailed",
      label: permissionsActionStatusLabel,
      isError: !didOpen
    )
  }

  @objc private func openNotificationSettings() {
    let didOpen = preferencesDelegate?.preferencesDidRequestNotificationSettings() ?? false
    requestNotificationPermissionStatus()
    setActionStatus(
      didOpen ? "preferences.actionOpenedNotificationSettings" : "preferences.actionOpenNotificationSettingsFailed",
      label: permissionsActionStatusLabel,
      isError: !didOpen
    )
  }

  @objc private func retryPermissionCheck() {
    let isTrusted = preferencesDelegate?.preferencesDidRequestPermissionCheck() ?? permissionManager.isTrusted
    refresh()
    setActionStatus(
      isTrusted ? "preferences.actionPermissionGranted" : "preferences.actionPermissionStillRequired",
      label: permissionsActionStatusLabel,
      isError: !isTrusted
    )
  }

  @objc private func sendTestNotification() {
    setActionStatus("preferences.actionSendingTestNotification", label: permissionsActionStatusLabel)
    preferencesDelegate?.preferencesDidRequestTestNotification { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.refresh()
        self.requestNotificationPermissionStatus()
        switch result {
        case .scheduled, .delivered:
          self.setActionStatus("preferences.actionTestNotificationSent", label: self.permissionsActionStatusLabel)
        case let .notDelivered(reason):
          self.setActionStatus(
            "preferences.actionTestNotificationNotDelivered",
            argument: reason,
            label: self.permissionsActionStatusLabel,
            isError: true
          )
        case .authorizationDenied:
          self.setActionStatus(
            "preferences.actionTestNotificationDenied",
            label: self.permissionsActionStatusLabel,
            isError: true
          )
        case let .failed(message):
          self.setActionStatus(
            "preferences.actionTestNotificationFailed",
            argument: message,
            label: self.permissionsActionStatusLabel,
            isError: true
          )
        }
      }
    }
  }

  @objc private func toggleDebugLogging() {
    preferences.debugLoggingEnabled = debugLoggingButton.state == .on
    setActionStatus(
      preferences.debugLoggingEnabled ? "preferences.actionDebugLoggingEnabled" : "preferences.actionDebugLoggingDisabled",
      label: advancedActionStatusLabel
    )
  }

  @objc private func restartWatcher() {
    let didRestart = preferencesDelegate?.preferencesDidRequestRestartWatcher() ?? false
    setActionStatus(
      didRestart ? "preferences.actionWatcherRestarted" : "preferences.actionWatcherRestartNeedsPermission",
      label: advancedActionStatusLabel,
      isError: !didRestart
    )
  }

  @objc private func openLogFile() {
    let didOpen = NSWorkspace.shared.open(logger.logFileURL)
    setActionStatus(
      didOpen ? "preferences.actionOpenedLogFile" : "preferences.actionOpenLogFileFailed",
      label: advancedActionStatusLabel,
      isError: !didOpen
    )
  }

  @objc private func copyDiagnosticsSummary() {
    NSPasteboard.general.clearContents()
    let didCopy = NSPasteboard.general.setString(diagnosticsSummary(), forType: .string)
    setActionStatus(
      didCopy ? "preferences.actionDiagnosticsCopied" : "preferences.actionDiagnosticsCopyFailed",
      label: advancedActionStatusLabel,
      isError: !didCopy
    )
  }

  @objc private func exportDiagnostics() {
    do {
      let url = try diagnosticsExporter.export()
      NSWorkspace.shared.activateFileViewerSelecting([url])
      setActionStatus("preferences.actionDiagnosticsExported", label: advancedActionStatusLabel)
    } catch {
      setActionStatus(
        "preferences.actionDiagnosticsExportFailed",
        argument: error.localizedDescription,
        label: advancedActionStatusLabel,
        isError: true
      )
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
    let displays = NSScreen.screens.count
    let lastTest = preferences.lastTestNotificationResult ?? L10n.text("preferences.lastTestResultNone")

    return """
    Noti Shift Diagnostics Summary
    App Version: \(appVersion)
    Build: \(buildVersion)
    macOS: \(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)
    Enabled: \(enabled)
    Accessibility: \(accessibility)
    Position: \(preferences.selectedPosition.displayName)
    Displays: \(displays)
    Automatically Check for Updates: \(automaticUpdates)
    Debug Logging: \(debugLogging)
    Last Test: \(lastTest)
    """
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
