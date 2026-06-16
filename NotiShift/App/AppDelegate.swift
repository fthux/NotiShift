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
    UNUserNotificationCenter.current().delegate = self
    menuBarController.delegate = self
    menuBarController.install()
    preferencesWindowController.preferencesDelegate = self
    onboardingWindowController.onboardingDelegate = self
    _ = permissionManager.requestIfNeeded(prompt: true)

    if permissionManager.isTrusted {
      startWatcherIfNeeded()
    } else {
      AppLogger.shared.info("Accessibility permission missing")
      startPermissionPolling()
    }
    menuBarController.rebuildMenu()

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
    let canRelocate = ensureAccessibilityForRelocation(action: "send system notification")
    if canRelocate {
      watcher.moveAll()
      watcher.moveRepeatedly()
    }
    NSApp.hide(nil)
    testNotificationSender.send()
    if canRelocate {
      schedulePostNotificationRelocation()
    }
  }

  func menuBarControllerDidRequestNotificationSettings() {
    testNotificationSender.openNotificationSettings()
  }

  func menuBarControllerDidRequestPreferences() {
    preferencesWindowController.showWindow(nil)
  }

  func menuBarControllerDidRequestPermissionCheck() {
    _ = permissionManager.requestIfNeeded(prompt: false)
    if permissionManager.isTrusted {
      startWatcherIfNeeded()
    }
    menuBarController.rebuildMenu()
  }

  func menuBarControllerDidRequestRestartWatcher() {
    guard permissionManager.isTrusted else {
      permissionManager.openAccessibilitySettings()
      return
    }
    watcher.restart()
  }

  func preferencesDidRequestPermissionCheck() {
    menuBarControllerDidRequestPermissionCheck()
  }

  func preferencesDidRequestNotificationSettings() {
    menuBarControllerDidRequestNotificationSettings()
  }

  func preferencesDidRequestTestNotification() {
    menuBarControllerDidRequestTestNotification()
  }

  func preferencesDidRequestRestartWatcher() {
    menuBarControllerDidRequestRestartWatcher()
  }

  func preferencesDidChangeLanguage() {
    menuBarController.rebuildMenu()
  }

  func onboardingDidRequestAccessibilitySettings() {
    permissionManager.openAccessibilitySettings()
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

  private func startPermissionPolling() {
    guard permissionTimer == nil else { return }
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
      guard let self else { return }
      if self.permissionManager.isTrusted {
        AppLogger.shared.info("Accessibility permission granted")
        self.startWatcherIfNeeded()
        self.menuBarController.rebuildMenu()
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
      menuBarController.rebuildMenu()
      return true
    }

    showAccessibilityRequiredAlert()
    startPermissionPolling()
    menuBarController.rebuildMenu()
    return false
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
    guard !preferences.hasCompletedOnboarding else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.onboardingWindowController.showWindow(nil)
    }
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
