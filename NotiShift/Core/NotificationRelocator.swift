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
  private var provisionalMoveGraceUntil: Date?

  init(detector: NotificationBannerDetector, preferences: NotiShiftPreferences) {
    self.detector = detector
    self.preferences = preferences
  }

  func move(windows: [AXUIElement]) {
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
    provisionalMoveGraceUntil = nil
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
      if let windowFrame = window.nsFrame(),
        moveProvisionallyIfNeeded(window, windowFrame: windowFrame)
      {
        return true
      }
      logger.debug("Skipping window without detected banner: \(window.nsSummary())")
      return false
    }

    provisionalMoveGraceUntil = nil

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

  private func moveProvisionallyIfNeeded(_ window: AXUIElement, windowFrame: CGRect) -> Bool {
    if let provisionalMoveGraceUntil, provisionalMoveGraceUntil > Date(), windowIsShifted {
      return true
    }

    guard shouldProvisionallyMove(window, windowFrame: windowFrame) else { return false }
    let estimatedBannerFrame = estimatedBannerFrame(for: windowFrame)
    guard let target = targetOrigin(for: windowFrame, bannerFrame: estimatedBannerFrame) else {
      logger.debug("No containing screen for provisional notification window")
      return false
    }

    if originalWindowOrigin == nil {
      originalWindowOrigin = windowFrame.origin
      logger.debug("Captured provisional origin window=\(NSStringFromRect(windowFrame))")
    }

    let result = window.nsSetPosition(target)
    windowIsShifted = result == .success
    if result == .success {
      provisionalMoveGraceUntil = Date().addingTimeInterval(0.45)
    }
    logger.debug(
      "Provisional window position result=\(result.nsName) target=\(NSStringFromPoint(target)) window=\(NSStringFromRect(windowFrame)) estimatedBanner=\(NSStringFromRect(estimatedBannerFrame))"
    )
    return result == .success
  }

  private func shouldProvisionallyMove(_ window: AXUIElement, windowFrame: CGRect) -> Bool {
    guard shouldUseProvisionalMove else { return false }
    guard window.nsIsSettable(kAXPositionAttribute) else { return false }
    guard let screen = mapper.containingScreen(forAXFrame: windowFrame) else { return false }

    let role = window.nsAttribute(kAXRoleAttribute, as: String.self) ?? ""
    guard role == kAXWindowRole as String || role == "AXWindow" else { return false }

    guard windowFrame.width >= 180 &&
      windowFrame.width <= 760 &&
      windowFrame.height >= 45 &&
      windowFrame.height <= 380
    else { return false }

    if originalWindowOrigin == nil {
      let rightInset = abs(screen.visibleFrame.maxX - windowFrame.maxX)
      let isNearRightEdge = rightInset <= 120
      let isNearTopEdge = windowFrame.minY <= 220
      return isNearRightEdge && isNearTopEdge
    }

    return true
  }

  private var shouldUseProvisionalMove: Bool {
    switch preferences.selectedPosition {
    case .topLeft, .topCenter, .topRight:
      false
    case .middleLeft, .center, .middleRight, .bottomLeft, .bottomCenter, .bottomRight:
      true
    }
  }

  private func estimatedBannerFrame(for windowFrame: CGRect) -> CGRect {
    let width = stablePlacementWidth(for: windowFrame.width)
    let height = min(max(windowFrame.height, 70), 180)
    let x = windowFrame.minX + stableLocalBannerX(windowWidth: windowFrame.width, bannerWidth: width)
    return CGRect(x: x, y: windowFrame.minY, width: width, height: height)
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
