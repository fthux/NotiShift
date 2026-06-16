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

func dump(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 8) {
  let indent = String(repeating: "  ", count: depth)
  let role = attribute(element, kAXRoleAttribute, as: String.self) ?? "?"
  let subrole = attribute(element, kAXSubroleAttribute, as: String.self) ?? "?"
  let identifier = attribute(element, kAXIdentifierAttribute, as: String.self) ?? ""
  let title = attribute(element, kAXTitleAttribute, as: String.self) ?? ""
  let desc = attribute(element, kAXDescriptionAttribute, as: String.self) ?? ""
  let frameText = frame(element).map(NSStringFromRect) ?? "nil"
  print("\(indent)\(role) sub=\(subrole) id=\(identifier) title=\(title) desc=\(desc) frame=\(frameText)")
  guard depth < maxDepth else { return }
  for child in children(element) {
    dump(child, depth: depth + 1, maxDepth: maxDepth)
  }
}

let apps = NSWorkspace.shared.runningApplications.filter {
  ($0.bundleIdentifier ?? "").contains("notificationcenter") ||
    ($0.localizedName ?? "").localizedCaseInsensitiveContains("Notification")
}

for app in apps {
  print("APP pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "?") name=\(app.localizedName ?? "?")")
  let root = AXUIElementCreateApplication(app.processIdentifier)
  let windows = attribute(root, kAXWindowsAttribute, as: [AXUIElement].self) ?? []
  print("windows=\(windows.count)")
  for (index, window) in windows.enumerated() {
    print("WINDOW \(index)")
    dump(window)
  }
}
