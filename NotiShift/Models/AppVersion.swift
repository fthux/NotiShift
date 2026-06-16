import Foundation

struct AppVersion: Comparable {
  let components: [Int]

  init?(_ string: String) {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
      ? String(trimmed.dropFirst())
      : trimmed
    let parts = normalized.split(separator: ".")
    guard !parts.isEmpty else { return nil }

    let components = parts.map { part -> Int? in
      let numericPrefix = part.prefix { $0.isNumber }
      guard !numericPrefix.isEmpty else { return nil }
      return Int(numericPrefix)
    }
    guard components.allSatisfy({ $0 != nil }) else { return nil }
    self.components = components.compactMap { $0 }
  }

  static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    let count = max(lhs.components.count, rhs.components.count)
    for index in 0..<count {
      let lhsValue = index < lhs.components.count ? lhs.components[index] : 0
      let rhsValue = index < rhs.components.count ? rhs.components[index] : 0
      if lhsValue != rhsValue {
        return lhsValue < rhsValue
      }
    }
    return false
  }
}
