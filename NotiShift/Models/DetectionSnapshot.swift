import ApplicationServices
import CoreGraphics
import Foundation

struct DetectionSnapshot {
  let window: AXUIElement
  let banner: AXUIElement
  let windowFrame: CGRect
  let bannerFrame: CGRect
  let detectionReason: String
}
