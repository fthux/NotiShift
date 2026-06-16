import ApplicationServices
import CoreGraphics
import Foundation

extension AXUIElement {
  func nsAttribute<T>(_ name: String, as _: T.Type = T.self) -> T? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else {
      return nil
    }
    return value as? T
  }

  func nsPoint(for attributeName: String) -> CGPoint? {
    guard
      let value = nsAttribute(attributeName, as: AXValue.self),
      AXValueGetType(value) == .cgPoint
    else {
      return nil
    }
    var point = CGPoint.zero
    AXValueGetValue(value, .cgPoint, &point)
    return point
  }

  func nsSize(for attributeName: String) -> CGSize? {
    guard
      let value = nsAttribute(attributeName, as: AXValue.self),
      AXValueGetType(value) == .cgSize
    else {
      return nil
    }
    var size = CGSize.zero
    AXValueGetValue(value, .cgSize, &size)
    return size
  }

  func nsFrame() -> CGRect? {
    guard let origin = nsPoint(for: kAXPositionAttribute),
      let size = nsSize(for: kAXSizeAttribute)
    else { return nil }
    return CGRect(origin: origin, size: size)
  }

  func nsIsSettable(_ attribute: String) -> Bool {
    var settable: DarwinBoolean = false
    let result = AXUIElementIsAttributeSettable(self, attribute as CFString, &settable)
    return result == .success && settable.boolValue
  }

  func nsSetPosition(_ point: CGPoint) -> AXError {
    var mutablePoint = point
    guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return .failure }
    return AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value)
  }

  func nsChildren() -> [AXUIElement] {
    let direct = nsAttribute(kAXChildrenAttribute, as: [AXUIElement].self) ?? []
    let ordered = nsAttribute(AppConstants.orderedChildrenAttribute, as: [AXUIElement].self) ?? []
    var seen = Set<ObjectIdentifier>()
    return (direct + ordered).filter { seen.insert(ObjectIdentifier($0)).inserted }
  }

  func nsFirstDescendant(maxDepth: Int = 12, where predicate: (AXUIElement) -> Bool)
    -> AXUIElement?
  {
    if predicate(self) { return self }
    guard maxDepth > 0 else { return nil }
    for child in nsChildren() {
      if let match = child.nsFirstDescendant(maxDepth: maxDepth - 1, where: predicate) {
        return match
      }
    }
    return nil
  }

  func nsSummary() -> String {
    let role = nsAttribute(kAXRoleAttribute, as: String.self) ?? "?"
    let subrole = nsAttribute(kAXSubroleAttribute, as: String.self) ?? "?"
    let identifier = nsAttribute(kAXIdentifierAttribute, as: String.self) ?? ""
    let title = nsAttribute(kAXTitleAttribute, as: String.self) ?? ""
    let frame = nsFrame().map(NSStringFromRect) ?? "nil"
    return "role=\(role) subrole=\(subrole) identifier=\(identifier) title=\(title) frame=\(frame)"
  }
}

extension AXError {
  var nsName: String {
    switch self {
    case .success: "success"
    case .failure: "failure"
    case .illegalArgument: "illegalArgument"
    case .invalidUIElement: "invalidUIElement"
    case .invalidUIElementObserver: "invalidUIElementObserver"
    case .cannotComplete: "cannotComplete"
    case .attributeUnsupported: "attributeUnsupported"
    case .actionUnsupported: "actionUnsupported"
    case .notificationUnsupported: "notificationUnsupported"
    case .notImplemented: "notImplemented"
    case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
    case .notificationNotRegistered: "notificationNotRegistered"
    case .apiDisabled: "apiDisabled"
    case .noValue: "noValue"
    case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: "notEnoughPrecision"
    @unknown default: "unknown(\(rawValue))"
    }
  }
}
