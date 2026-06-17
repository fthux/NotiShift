import AppKit
import Foundation
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarControllerDelegate, PreferencesWindowControllerDelegate, OnboardingWindowControllerDelegate, UNUserNotificationCenterDelegate {
  private let preferences = NotiShiftPreferences.shared
  private let permissionManager = AccessibilityPermissionManager()
  private let launchAtLoginManager = LaunchAtLoginManager()
  private let testNotificationSender = TestNotificationSender()
  private let updateChecker = UpdateChecker()
  private let profile = CompatibilityProfile.current
  private lazy var diagnosticsExporter = DiagnosticsExporter(profile: profile)
  private var permissionTimer: Timer?
  private var watcherIsStarted = false
  private lazy var watcher = NotificationCenterWatcher(profile: profile, preferences: preferences)
  private lazy var menuBarController = MenuBarController(preferences: preferences)
  private lazy var preferencesWindowController = PreferencesWindowController(
    preferences: preferences,
    permissionManager: permissionManager,
    launchAtLoginManager: launchAtLoginManager,
    diagnosticsExporter: diagnosticsExporter,
    updateChecker: updateChecker
  )
  private lazy var onboardingWindowController = OnboardingWindowController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppLogger.shared.info("NotiShift launch started profile=\(profile.generation.rawValue)")
    NSApp.setActivationPolicy(.accessory)
    applySelectedTheme()
    UNUserNotificationCenter.current().delegate = self
    menuBarController.delegate = self
    menuBarController.install()
    preferencesWindowController.preferencesDelegate = self
    onboardingWindowController.onboardingDelegate = self

    if permissionManager.isTrusted {
      startWatcherIfNeeded()
    } else {
      AppLogger.shared.info("Accessibility permission missing")
      startPermissionPolling()
    }
    refreshMenuPermissionStatus()

    if CommandLine.arguments.contains("--send-system-notification") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
        self?.menuBarControllerDidRequestTestNotification()
      }
    }

    scheduleAutomaticUpdateCheckIfNeeded()
    showOnboardingIfNeeded()
  }

  func applicationWillTerminate(_ notification: Notification) {
    permissionTimer?.invalidate()
    watcher.stop()
  }

  func menuBarControllerDidToggleEnabled() {
    if ensureAccessibilityForRelocation(action: "toggle enabled") {
      watcher.moveAll()
      watcher.moveRepeatedly()
    }
  }

  func menuBarControllerDidSelectPosition() {
    if ensureAccessibilityForRelocation(action: "select position") {
      watcher.restart()
      watcher.moveAll()
      watcher.moveRepeatedly()
    }
  }

  func menuBarControllerDidRequestTestNotification() {
    sendTestNotification(hideApp: true)
  }

  private func sendTestNotification(hideApp: Bool, completion: ((TestNotificationResult) -> Void)? = nil) {
    let canRelocate = ensureAccessibilityForRelocation(action: "send system notification")
    if canRelocate {
      watcher.moveAll()
      watcher.moveRepeatedly()
    }
    if hideApp {
      NSApp.hide(nil)
    }
    testNotificationSender.send { result in
      DispatchQueue.main.async {
        completion?(result)
      }
    }
    if canRelocate {
      schedulePostNotificationRelocation()
    }
  }

  @discardableResult
  func menuBarControllerDidRequestNotificationSettings() -> Bool {
    let didOpen = testNotificationSender.openNotificationSettings()
    refreshMenuPermissionStatus()
    return didOpen
  }

  func menuBarControllerDidRequestPreferences() {
    preferencesWindowController.showWindow(nil)
  }

  func menuBarControllerDidRequestAccessibilitySettings() {
    permissionManager.openAccessibilitySettings()
    startPermissionPolling()
    refreshMenuPermissionStatus()
  }

  @discardableResult
  func menuBarControllerDidRequestPermissionCheck() -> Bool {
    _ = permissionManager.requestIfNeeded(prompt: false)
    if permissionManager.isTrusted {
      startWatcherIfNeeded()
    }
    refreshMenuPermissionStatus()
    return permissionManager.isTrusted
  }

  @discardableResult
  func menuBarControllerDidRequestRestartWatcher() -> Bool {
    guard permissionManager.isTrusted else {
      permissionManager.openAccessibilitySettings()
      return false
    }
    watcher.restart()
    return true
  }

  func preferencesDidRequestPermissionCheck() -> Bool {
    menuBarControllerDidRequestPermissionCheck()
  }

  func preferencesDidRequestNotificationPermissionStatus(completion: @escaping (NotificationPermissionStatus) -> Void) {
    testNotificationSender.permissionStatus(completion: completion)
  }

  func preferencesDidSelectPosition() {
    menuBarControllerDidSelectPosition()
    menuBarController.rebuildMenu()
  }

  func preferencesDidRequestNotificationSettings() -> Bool {
    menuBarControllerDidRequestNotificationSettings()
  }

  func preferencesDidRequestTestNotification(completion: @escaping (TestNotificationResult) -> Void) {
    sendTestNotification(hideApp: false, completion: completion)
  }

  func preferencesDidRequestRestartWatcher() -> Bool {
    menuBarControllerDidRequestRestartWatcher()
  }

  func preferencesDidRequestFeedbackNotification(title: String, body: String) {
    sendFeedbackNotification(title: title, body: body)
  }

  func preferencesDidChangeLanguage() {
    menuBarController.rebuildMenu()
  }

  func preferencesDidChangeTheme() {
    applySelectedTheme()
  }

  func onboardingDidRequestAccessibilitySettings() {
    permissionManager.openAccessibilitySettings()
    startPermissionPolling()
  }

  func onboardingDidRequestPreferences() {
    menuBarControllerDidRequestPreferences()
  }

  func onboardingDidFinish() {
    preferences.hasCompletedOnboarding = true
  }

  private func startWatcherIfNeeded() {
    guard !watcherIsStarted else { return }
    watcherIsStarted = true
    permissionTimer?.invalidate()
    permissionTimer = nil
    watcher.start()
  }

  private func applySelectedTheme() {
    NSApp.appearance = preferences.selectedTheme.appearance
  }

  private func startPermissionPolling() {
    guard permissionTimer == nil else { return }
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
      guard let self else { return }
      if self.permissionManager.isTrusted {
        AppLogger.shared.info("Accessibility permission granted")
        self.startWatcherIfNeeded()
        self.refreshMenuPermissionStatus()
      }
    }
    RunLoop.current.add(permissionTimer!, forMode: .common)
  }

  private func ensureAccessibilityForRelocation(action: String) -> Bool {
    if permissionManager.isTrusted {
      startWatcherIfNeeded()
      return true
    }

    AppLogger.shared.info(
      "Cannot relocate notification during \(action): Accessibility permission is missing"
    )
    _ = permissionManager.requestIfNeeded(prompt: true)

    if permissionManager.isTrusted {
      AppLogger.shared.info("Accessibility permission granted during \(action)")
      startWatcherIfNeeded()
      refreshMenuPermissionStatus()
      return true
    }

    showAccessibilityRequiredAlert()
    startPermissionPolling()
    refreshMenuPermissionStatus()
    return false
  }

  private func refreshMenuPermissionStatus() {
    menuBarController.accessibilityPermissionGranted = permissionManager.isTrusted
    testNotificationSender.permissionStatus { [weak self] status in
      DispatchQueue.main.async {
        guard let self else { return }
        self.menuBarController.notificationPermissionStatus = status
        self.menuBarController.accessibilityPermissionGranted = self.permissionManager.isTrusted
        self.menuBarController.rebuildMenu()
      }
    }
    menuBarController.rebuildMenu()
  }

  private func showAccessibilityRequiredAlert() {
    let alert = NSAlert()
    alert.messageText = L10n.text("alert.accessibilityRequired")
    alert.informativeText = L10n.text("alert.accessibilityRequiredMessage")
    alert.addButton(withTitle: L10n.text("button.openSettings"))
    alert.addButton(withTitle: L10n.text("button.ok"))

    if alert.runModal() == .alertFirstButtonReturn {
      permissionManager.openAccessibilitySettings()
    }
  }

  private func schedulePostNotificationRelocation() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.watcher.moveRepeatedly()
    }
  }

  private func sendFeedbackNotification(title: String, body: String) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      if let error {
        AppLogger.shared.error("Feedback notification authorization failed: \(error.localizedDescription)")
        return
      }
      guard granted else {
        AppLogger.shared.info("Feedback notification authorization denied")
        return
      }

      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default

      let request = UNNotificationRequest(
        identifier: "notishift-feedback-\(UUID().uuidString)",
        content: content,
        trigger: nil
      )
      center.add(request) { error in
        if let error {
          AppLogger.shared.error("Failed to deliver feedback notification: \(error.localizedDescription)")
        }
      }
    }
  }

  private func scheduleAutomaticUpdateCheckIfNeeded() {
    guard preferences.automaticallyCheckForUpdates else { return }
    if let lastUpdateCheckAt = preferences.lastUpdateCheckAt,
      Date().timeIntervalSince(lastUpdateCheckAt) < 24 * 60 * 60
    {
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
      guard let self, self.preferences.automaticallyCheckForUpdates else { return }
      Task { @MainActor in
        await self.preferencesWindowController.showUpdateCheckResult(showUpToDate: false)
      }
    }
  }

  private func showOnboardingIfNeeded() {
    guard shouldShowOnboarding else { return }
    preferences.lastOnboardingPromptVersion = currentAppVersion
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.onboardingWindowController.showWindow(nil)
    }
  }

  private var shouldShowOnboarding: Bool {
    if !preferences.hasCompletedOnboarding {
      return true
    }
    guard !permissionManager.isTrusted else {
      return false
    }
    return preferences.lastOnboardingPromptVersion != currentAppVersion
  }

  private var currentAppVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    AppLogger.shared.info("Presenting foreground notification via completion id=\(notification.request.identifier)")
    completionHandler([.banner, .list, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    AppLogger.shared.info("Received notification response id=\(response.notification.request.identifier)")
    completionHandler()
  }
}

private extension AppTheme {
  var appearance: NSAppearance? {
    switch self {
    case .system:
      nil
    case .light:
      NSAppearance(named: .aqua)
    case .dark:
      NSAppearance(named: .darkAqua)
    }
  }
}
