import AppKit
import CoreGraphics
import Foundation

struct NotificationCenterProcess {
  let pid: pid_t
  let bundleIdentifier: String?
  let localizedName: String?
}

final class NotificationCenterProcessResolver {
  private let profile: CompatibilityProfile
  private let logger = AppLogger.shared

  init(profile: CompatibilityProfile) {
    self.profile = profile
  }

  func resolve() -> NotificationCenterProcess? {
    if let app = NSWorkspace.shared.runningApplications.first(where: { app in
      guard let bundleIdentifier = app.bundleIdentifier else { return false }
      return profile.notificationCenterBundleIDs.contains(bundleIdentifier)
    }) {
      return NotificationCenterProcess(
        pid: app.processIdentifier,
        bundleIdentifier: app.bundleIdentifier,
        localizedName: app.localizedName
      )
    }

    if let app = NSWorkspace.shared.runningApplications.first(where: { app in
      let name = [app.localizedName, app.bundleIdentifier].compactMap { $0 }.joined(separator: " ")
      return profile.notificationCenterNameFragments.contains { fragment in
        name.localizedCaseInsensitiveContains(fragment)
      }
    }) {
      return NotificationCenterProcess(
        pid: app.processIdentifier,
        bundleIdentifier: app.bundleIdentifier,
        localizedName: app.localizedName
      )
    }

    if let pid = resolveFromCGWindowList() {
      return NotificationCenterProcess(pid: pid, bundleIdentifier: nil, localizedName: nil)
    }

    logger.debug("Notification Center process not found")
    return nil
  }

  private func resolveFromCGWindowList() -> pid_t? {
    guard let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]] else {
      return nil
    }

    for item in windowInfo {
      let ownerName = item[kCGWindowOwnerName as String] as? String ?? ""
      guard profile.notificationCenterNameFragments.contains(where: {
        ownerName.localizedCaseInsensitiveContains($0)
      }) else { continue }

      if let pid = item[kCGWindowOwnerPID as String] as? pid_t {
        return pid
      }
      if let pidNumber = item[kCGWindowOwnerPID as String] as? NSNumber {
        return pidNumber.int32Value
      }
    }

    return nil
  }
}
