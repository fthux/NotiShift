import CoreGraphics
import Foundation

struct CGWindowSnapshot {
  let ownerPID: pid_t
  let ownerName: String
  let bounds: CGRect
  let layer: Int
  let alpha: Double
  let isOnscreen: Bool
}

final class CGWindowInspector {
  func snapshots(for pid: pid_t? = nil) -> [CGWindowSnapshot] {
    guard let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements],
      kCGNullWindowID
    ) as? [[String: Any]] else {
      return []
    }

    return windowInfo.compactMap { item in
      let itemPID: pid_t?
      if let value = item[kCGWindowOwnerPID as String] as? pid_t {
        itemPID = value
      } else if let value = item[kCGWindowOwnerPID as String] as? NSNumber {
        itemPID = value.int32Value
      } else {
        itemPID = nil
      }

      guard let itemPID else { return nil }
      if let pid, itemPID != pid { return nil }

      let ownerName = item[kCGWindowOwnerName as String] as? String ?? ""
      let layer = (item[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
      let alpha = (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
      let isOnscreen = (item[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
      var bounds = CGRect.zero
      if let boundsDictionary = item[kCGWindowBounds as String] as? NSDictionary {
        CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds)
      }

      return CGWindowSnapshot(
        ownerPID: itemPID,
        ownerName: ownerName,
        bounds: bounds,
        layer: layer,
        alpha: alpha,
        isOnscreen: isOnscreen
      )
    }
  }
}
