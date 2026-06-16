import AppKit
import CoreGraphics
import Foundation

final class CoordinateMapper {
  func containingScreen(forAXFrame frame: CGRect) -> NSScreen? {
    let globalTopY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
    let appKitPoint = CGPoint(
      x: frame.midX,
      y: globalTopY - frame.midY
    )
    return NSScreen.screens.first { $0.frame.contains(appKitPoint) }
  }

  func appKitFrame(fromAXFrame frame: CGRect) -> CGRect {
    let globalTopY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
    return CGRect(
      x: frame.minX,
      y: globalTopY - frame.maxY,
      width: frame.width,
      height: frame.height
    )
  }
}
