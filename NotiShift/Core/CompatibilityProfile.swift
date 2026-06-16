import Foundation

enum MacOSGeneration: String {
  case catalinaOrOlder
  case bigSur
  case monterey
  case ventura
  case sonoma
  case sequoia
  case tahoeOrNewer
  case unknown
}

struct CompatibilityProfile {
  let generation: MacOSGeneration
  let notificationCenterBundleIDs: [String]
  let notificationCenterNameFragments: [String]
  let bannerSubroles: Set<String>
  let panelIdentifiers: Set<String>
  let enablePollingFallback: Bool

  static var current: CompatibilityProfile {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let generation: MacOSGeneration

    switch version.majorVersion {
    case ...10:
      generation = .catalinaOrOlder
    case 11:
      generation = .bigSur
    case 12:
      generation = .monterey
    case 13:
      generation = .ventura
    case 14:
      generation = .sonoma
    case 15:
      generation = .sequoia
    case 26...:
      generation = .tahoeOrNewer
    default:
      generation = .unknown
    }

    return CompatibilityProfile(
      generation: generation,
      notificationCenterBundleIDs: [
        "com.apple.notificationcenterui",
        "com.apple.NotificationCenter",
        "com.apple.notificationcenter",
      ],
      notificationCenterNameFragments: [
        "Notification Center",
        "NotificationCenter",
        "notificationcenterui",
      ],
      bannerSubroles: [
        "AXNotificationCenterBanner",
        "AXNotificationCenterAlert",
        "AXNotificationCenterNotification",
        "AXNotificationCenterBannerWindow",
      ],
      panelIdentifiers: [
        "widget-editor-button",
      ],
      enablePollingFallback: true
    )
  }
}
