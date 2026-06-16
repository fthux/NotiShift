import ApplicationServices
import AppKit
import Foundation

func attribute<T>(_ element: AXUIElement, _ name: String, as _: T.Type = T.self) -> T? {
  var value: AnyObject?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
    return nil
  }
  return value as? T
}

func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
  guard let value = attribute(element, name, as: AXValue.self), AXValueGetType(value) == .cgPoint else {
    return nil
  }
  var point = CGPoint.zero
  AXValueGetValue(value, .cgPoint, &point)
  return point
}

func size(_ element: AXUIElement, _ name: String) -> CGSize? {
  guard let value = attribute(element, name, as: AXValue.self), AXValueGetType(value) == .cgSize else {
    return nil
  }
  var size = CGSize.zero
  AXValueGetValue(value, .cgSize, &size)
  return size
}

func frame(_ element: AXUIElement) -> CGRect? {
  guard let origin = point(element, kAXPositionAttribute), let size = size(element, kAXSizeAttribute) else {
    return nil
  }
  return CGRect(origin: origin, size: size)
}

func children(_ element: AXUIElement) -> [AXUIElement] {
  let direct = attribute(element, kAXChildrenAttribute, as: [AXUIElement].self) ?? []
  let ordered = attribute(element, "AXOrderedChildren", as: [AXUIElement].self) ?? []
  var seen = Set<ObjectIdentifier>()
  return (direct + ordered).filter { seen.insert(ObjectIdentifier($0)).inserted }
}

func firstDescendant(_ element: AXUIElement, maxDepth: Int = 12, where predicate: (AXUIElement) -> Bool) -> AXUIElement? {
  if predicate(element) { return element }
  guard maxDepth > 0 else { return nil }
  for child in children(element) {
    if let match = firstDescendant(child, maxDepth: maxDepth - 1, where: predicate) {
      return match
    }
  }
  return nil
}

func plausibleBannerSize(_ size: CGSize) -> Bool {
  size.width >= 180 && size.width <= 720 && size.height >= 45 && size.height <= 360
}

func setPosition(_ element: AXUIElement, _ point: CGPoint) -> AXError {
  var mutablePoint = point
  guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return .failure }
  return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
}

let apps = NSWorkspace.shared.runningApplications.filter {
  ($0.bundleIdentifier ?? "").contains("notificationcenter") ||
    ($0.localizedName ?? "").localizedCaseInsensitiveContains("Notification Center")
}

guard let app = apps.first else {
  print("Notification Center app not found")
  exit(1)
}

let root = AXUIElementCreateApplication(app.processIdentifier)
let windows = attribute(root, kAXWindowsAttribute, as: [AXUIElement].self) ?? []

guard let window = windows.first, let windowFrame = frame(window) else {
  print("Notification Center window not found")
  exit(1)
}

let bannerSubroles: Set<String> = [
  "AXNotificationCenterBanner",
  "AXNotificationCenterAlert",
  "AXNotificationCenterNotification",
  "AXNotificationCenterBannerWindow",
]

guard
  let banner = firstDescendant(window, where: { element in
    guard
      let subrole = attribute(element, kAXSubroleAttribute, as: String.self),
      bannerSubroles.contains(subrole),
      let elementFrame = frame(element),
      plausibleBannerSize(elementFrame.size)
    else {
      return false
    }
    return true
  }),
  let bannerFrame = frame(banner)
else {
  print("Notification banner not found")
  exit(1)
}

let targetBannerX = (NSScreen.main?.frame.minX ?? 0) + 16
let localBannerX = bannerFrame.minX - windowFrame.minX
let target = CGPoint(x: targetBannerX - localBannerX, y: windowFrame.minY)
let result = setPosition(window, target)
let afterWindow = frame(window).map(NSStringFromRect) ?? "nil"
let afterBanner = frame(banner).map(NSStringFromRect) ?? "nil"

print("beforeWindow=\(NSStringFromRect(windowFrame))")
print("beforeBanner=\(NSStringFromRect(bannerFrame))")
print("targetWindowOrigin=\(NSStringFromPoint(target))")
print("result=\(result.rawValue)")
print("afterWindow=\(afterWindow)")
print("afterBanner=\(afterBanner)")
