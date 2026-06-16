import Foundation
import AppKit
import UserNotifications

final class TestNotificationSender {
  private let logger = AppLogger.shared

  func send() {
    logAppNotificationSettings()
    sendModernUserNotification()
  }

  private func logAppNotificationSettings() {
    let center = UNUserNotificationCenter.current()
    let options: UNAuthorizationOptions
    if #available(macOS 12.0, *) {
      options = [.alert, .sound, .badge, .timeSensitive]
    } else {
      options = [.alert, .sound, .badge]
    }

    center.requestAuthorization(options: options) { [weak self] granted, error in
      if let error {
        self?.logger.error("Notification authorization failed: \(error.localizedDescription)")
        return
      }

      guard granted else {
        self?.logger.info("Notification authorization denied")
        return
      }

      center.getNotificationSettings { settings in
        self?.logger.info(
          "Notification settings authorization=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) sound=\(settings.soundSetting.rawValue) alertStyle=\(settings.alertStyle.rawValue)"
        )
      }
    }
  }

  func openNotificationSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.notifications",
    ]
    for candidate in candidates {
      guard let url = URL(string: candidate) else { continue }
      if NSWorkspace.shared.open(url) { return }
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }

  private func sendModernUserNotification() {
    let center = UNUserNotificationCenter.current()
    let content = UNMutableNotificationContent()
    content.title = L10n.text("notification.testTitle")
    content.subtitle = L10n.text("notification.testSubtitle")
    content.body = L10n.text("notification.testBody")
    content.sound = .default
    content.threadIdentifier = "notishift-test"
    content.categoryIdentifier = "notishift-test"
    if #available(macOS 12.0, *) {
      content.interruptionLevel = .timeSensitive
    }

    let request = UNNotificationRequest(
      identifier: "notishift-modern-\(UUID().uuidString)",
      content: content,
      trigger: nil
    )

    center.add(request) { [weak self] error in
      if let error {
        self?.logger.error("Failed to deliver modern test notification: \(error.localizedDescription)")
      } else {
        self?.logger.info("Scheduled modern UNNotification request id=\(request.identifier)")
        center.getPendingNotificationRequests { requests in
          let contains = requests.contains { $0.identifier == request.identifier }
          self?.logger.info("Pending modern notification id=\(request.identifier) present=\(contains)")
        }
        center.getDeliveredNotifications { notifications in
          let contains = notifications.contains { $0.request.identifier == request.identifier }
          self?.logger.info("Delivered modern notification id=\(request.identifier) present=\(contains)")
        }
      }
    }
  }
}
