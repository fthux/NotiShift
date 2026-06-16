import ApplicationServices
import AppKit
import Foundation

final class NotificationBannerDetector {
  private let profile: CompatibilityProfile

  init(profile: CompatibilityProfile) {
    self.profile = profile
  }

  func detectionSnapshot(in window: AXUIElement) -> DetectionSnapshot? {
    guard let windowFrame = window.nsFrame() else { return nil }

    if let banner = exactBanner(in: window),
      let bannerFrame = banner.nsFrame()
    {
      return DetectionSnapshot(
        window: window,
        banner: banner,
        windowFrame: windowFrame,
        bannerFrame: bannerFrame,
        detectionReason: "exact-subrole"
      )
    }

    if let banner = heuristicBanner(in: window, windowFrame: windowFrame),
      let bannerFrame = banner.nsFrame()
    {
      return DetectionSnapshot(
        window: window,
        banner: banner,
        windowFrame: windowFrame,
        bannerFrame: bannerFrame,
        detectionReason: "heuristic"
      )
    }

    return nil
  }

  func notificationCenterPanelIsOpen(in root: AXUIElement) -> Bool {
    root.nsFirstDescendant { element in
      guard let identifier = element.nsAttribute(kAXIdentifierAttribute, as: String.self) else {
        return false
      }
      return profile.panelIdentifiers.contains(identifier)
    } != nil
  }

  private func exactBanner(in root: AXUIElement) -> AXUIElement? {
    root.nsFirstDescendant { element in
      guard let subrole = element.nsAttribute(kAXSubroleAttribute, as: String.self) else {
        return false
      }
      guard let frame = element.nsFrame(), plausibleBannerSize(frame.size) else {
        return false
      }
      return profile.bannerSubroles.contains(subrole)
    }
  }

  private func heuristicBanner(in root: AXUIElement, windowFrame: CGRect) -> AXUIElement? {
    root.nsFirstDescendant { element in
      guard let frame = element.nsFrame() else { return false }
      guard plausibleBannerSize(frame.size) else { return false }

      let role = element.nsAttribute(kAXRoleAttribute, as: String.self) ?? ""
      let subrole = element.nsAttribute(kAXSubroleAttribute, as: String.self) ?? ""
      let hasInterestingRole = [
        "AXGroup", "AXWindow", "AXDialog", "AXSystemDialog", "AXPopover",
      ].contains(role) || subrole.localizedCaseInsensitiveContains("notification")

      guard hasInterestingRole else { return false }
      guard frame != windowFrame else { return false }

      let isNearWindowEdge =
        abs(frame.minX - windowFrame.minX) < 80 ||
        abs(frame.maxX - windowFrame.maxX) < 80 ||
        abs(frame.minY - windowFrame.minY) < 80 ||
        abs(frame.maxY - windowFrame.maxY) < 80

      return isNearWindowEdge
    }
  }

  private func plausibleBannerSize(_ size: CGSize) -> Bool {
    size.width >= 180 &&
      size.width <= 720 &&
      size.height >= 45 &&
      size.height <= 360
  }
}
