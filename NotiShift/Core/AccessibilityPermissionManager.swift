import ApplicationServices
import AppKit
import Foundation

final class AccessibilityPermissionManager {
  var isTrusted: Bool {
    trustStatus(prompt: false)
  }

  @discardableResult
  func requestIfNeeded(prompt: Bool) -> Bool {
    trustStatus(prompt: prompt)
  }

  func trustStatus(prompt: Bool) -> Bool {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  @discardableResult
  func openAccessibilitySettings() -> Bool {
    let candidates = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
      "x-apple.systempreferences:com.apple.Security-Privacy.extension?Privacy_Accessibility",
    ]
    for candidate in candidates {
      guard let url = URL(string: candidate) else { continue }
      if NSWorkspace.shared.open(url) { return true }
    }
    return NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
