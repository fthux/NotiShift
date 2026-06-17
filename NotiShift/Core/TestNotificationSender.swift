import Foundation
import AppKit
import UserNotifications

enum NotificationPermissionStatus {
  case granted
  case denied
  case notDetermined
}

enum TestNotificationResult {
  case scheduled
  case delivered
  case notDelivered(String)
  case authorizationDenied
  case failed(String)
}

final class TestNotificationSender {
  private let logger = AppLogger.shared

  func permissionStatus(completion: @escaping (NotificationPermissionStatus) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        let canPresentAlert = settings.alertSetting == .enabled
        let hasVisibleAlertStyle: Bool
        if #available(macOS 11.0, *) {
          hasVisibleAlertStyle = settings.alertStyle != .none
        } else {
          hasVisibleAlertStyle = true
        }
        completion(canPresentAlert && hasVisibleAlertStyle ? .granted : .denied)
      case .denied:
        completion(.denied)
      case .notDetermined:
        completion(.notDetermined)
      @unknown default:
        completion(.notDetermined)
      }
    }
  }

  func send(completion: @escaping (TestNotificationResult) -> Void) {
    requestAuthorization { [weak self] result in
      switch result {
      case .scheduled:
        self?.sendModernUserNotification(completion: completion)
      case .delivered, .notDelivered, .authorizationDenied, .failed:
        completion(result)
      }
    }
  }

  private func requestAuthorization(completion: @escaping (TestNotificationResult) -> Void) {
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
        completion(.failed(error.localizedDescription))
        return
      }

      guard granted else {
        self?.logger.info("Notification authorization denied")
        completion(.authorizationDenied)
        return
      }

      center.getNotificationSettings { settings in
        self?.logger.info(
          "Notification settings authorization=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) sound=\(settings.soundSetting.rawValue) alertStyle=\(settings.alertStyle.rawValue)"
        )
        completion(.scheduled)
      }
    }
  }

  @discardableResult
  func openNotificationSettings() -> Bool {
    let candidates = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.notifications",
    ]
    for candidate in candidates {
      guard let url = URL(string: candidate) else { continue }
      if NSWorkspace.shared.open(url) { return true }
    }
    return NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }

  private func sendModernUserNotification(completion: @escaping (TestNotificationResult) -> Void) {
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
        completion(.failed(error.localizedDescription))
      } else {
        self?.logger.info("Scheduled modern UNNotification request id=\(request.identifier)")
        self?.confirmDelivery(for: request.identifier, completion: completion)
      }
    }
  }

  private func confirmDelivery(for requestIdentifier: String, completion: @escaping (TestNotificationResult) -> Void) {
    let center = UNUserNotificationCenter.current()
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
      center.getDeliveredNotifications { notifications in
        let isDelivered = notifications.contains { $0.request.identifier == requestIdentifier }
        self?.logger.info("Delivered modern notification id=\(requestIdentifier) present=\(isDelivered)")
        guard !isDelivered else {
          completion(.delivered)
          return
        }

        center.getPendingNotificationRequests { requests in
          let isPending = requests.contains { $0.identifier == requestIdentifier }
          self?.logger.info("Pending modern notification id=\(requestIdentifier) present=\(isPending)")
          let reason = isPending
            ? L10n.text("testResult.notDeliveredPending")
            : L10n.text("testResult.notDeliveredSuppressed")
          completion(.notDelivered(reason))
        }
      }
    }
  }
}
