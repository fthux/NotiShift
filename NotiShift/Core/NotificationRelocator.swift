import ApplicationServices
import AppKit
import Foundation

final class NotificationRelocator {
  private let detector: NotificationBannerDetector
  private let preferences: NotiShiftPreferences
  private let mapper = CoordinateMapper()
  private let logger = AppLogger.shared

  private var originalWindowOrigin: CGPoint?
  private var windowIsShifted = false

  init(detector: NotificationBannerDetector, preferences: NotiShiftPreferences) {
    self.detector = detector
    self.preferences = preferences
  }

  func move(windows: [AXUIElement]) {
    guard !preferences.isPaused else {
      restoreShiftedWindows(windows, reason: "paused")
      return
    }

    guard preferences.isEnabled else {
      restoreShiftedWindows(windows, reason: "disabled")
      return
    }

    var movedAny = false
    for window in windows {
      if move(window) {
        movedAny = true
      }
    }

    if !movedAny {
      restoreShiftedWindows(windows, reason: "no notification banner")
    }
  }

  func resetBaseline() {
    originalWindowOrigin = nil
    windowIsShifted = false
  }

  func restore(windows: [AXUIElement], reason: String) {
    restoreShiftedWindows(windows, reason: reason)
  }

  private func move(_ window: AXUIElement) -> Bool {
    if detector.notificationCenterPanelIsOpen(in: window) {
      restoreWindowIfNeeded(window, reason: "Notification Center panel opened")
      return false
    }

    guard let snapshot = detector.detectionSnapshot(in: window) else {
      logger.debug("Skipping window without detected banner: \(window.nsSummary())")
      return false
    }

    guard snapshot.window.nsIsSettable(kAXPositionAttribute) else {
      logger.debug("Window position not settable: \(snapshot.window.nsSummary())")
      return false
    }

    if originalWindowOrigin == nil {
      originalWindowOrigin = snapshot.windowFrame.origin
      logger.debug(
        "Captured original origin reason=\(snapshot.detectionReason) window=\(NSStringFromRect(snapshot.windowFrame)) banner=\(NSStringFromRect(snapshot.bannerFrame))"
      )
    }

    guard let target = targetOrigin(
      for: snapshot.windowFrame,
      bannerFrame: snapshot.bannerFrame
    ) else {
      logger.debug("No containing screen for notification window")
      return false
    }

    let result = snapshot.window.nsSetPosition(target)
    windowIsShifted = result == .success
    logger.debug(
      "Set window position result=\(result.nsName) target=\(NSStringFromPoint(target)) after=\(snapshot.window.nsFrame().map(NSStringFromRect) ?? "nil")"
    )
    return result == .success
  }

  private func restoreShiftedWindows(_ windows: [AXUIElement], reason: String) {
    guard windowIsShifted else { return }
    for window in windows {
      restoreWindowIfNeeded(window, reason: reason)
    }
  }

  private func restoreWindowIfNeeded(_ window: AXUIElement, reason: String) {
    guard windowIsShifted, let originalWindowOrigin else { return }
    guard window.nsIsSettable(kAXPositionAttribute) else { return }

    let result = window.nsSetPosition(originalWindowOrigin)
    logger.debug(
      "Restored window position reason=\(reason) result=\(result.nsName) target=\(NSStringFromPoint(originalWindowOrigin))"
    )
    if result == .success {
      resetBaseline()
    }
  }

  private func targetOrigin(for windowFrame: CGRect, bannerFrame: CGRect) -> CGPoint? {
    guard
      let screen = mapper.containingScreen(forAXFrame: bannerFrame) ??
        mapper.containingScreen(forAXFrame: windowFrame)
    else { return nil }
    let screenFrame = screen.frame
    let visibleFrame = screen.visibleFrame

    let measuredLocalBannerX = bannerFrame.minX - windowFrame.minX
    let localBannerY = bannerFrame.minY - windowFrame.minY
    let placementWidth = stablePlacementWidth(for: bannerFrame.width)
    let localBannerX = stableLocalBannerX(windowWidth: windowFrame.width, bannerWidth: placementWidth)
    let x: CGFloat
    switch preferences.selectedPosition {
    case .topLeft, .middleLeft, .bottomLeft:
      x = visibleFrame.minX + AppConstants.defaultEdgePadding - localBannerX
    case .topCenter, .center, .bottomCenter:
      x = visibleFrame.midX - placementWidth / 2 - localBannerX
    case .topRight, .middleRight, .bottomRight:
      x = visibleFrame.maxX - AppConstants.defaultEdgePadding - placementWidth - localBannerX
    }

    let dockOrMenuAllowance = max(0, screenFrame.height - visibleFrame.height)
    let y: CGFloat
    switch preferences.selectedPosition {
    case .topLeft, .topCenter, .topRight:
      y = windowFrame.minY
    case .middleLeft, .center, .middleRight:
      y = screenFrame.minY + (screenFrame.height - bannerFrame.height) / 2 -
        localBannerY -
        dockOrMenuAllowance -
        AppConstants.defaultDockPadding
    case .bottomLeft, .bottomCenter, .bottomRight:
      y = screenFrame.maxY - bannerFrame.height -
        localBannerY -
        dockOrMenuAllowance -
        AppConstants.defaultDockPadding
    }

    let target = CGPoint(x: x, y: y)
    logger.debug(
      "targetOrigin position=\(preferences.selectedPosition.rawValue) window=\(NSStringFromRect(windowFrame)) banner=\(NSStringFromRect(bannerFrame)) measuredLocalX=\(measuredLocalBannerX) stableLocalX=\(localBannerX) placementWidth=\(placementWidth) screen=\(NSStringFromRect(screenFrame)) visible=\(NSStringFromRect(visibleFrame)) target=\(NSStringFromPoint(target))"
    )
    return target
  }

  private func stableLocalBannerX(windowWidth: CGFloat, bannerWidth: CGFloat) -> CGFloat {
    max(0, windowWidth - bannerWidth - AppConstants.defaultEdgePadding)
  }

  private func stablePlacementWidth(for measuredWidth: CGFloat) -> CGFloat {
    if measuredWidth >= 260, measuredWidth <= 420 {
      return measuredWidth
    }
    return 344
  }
}
