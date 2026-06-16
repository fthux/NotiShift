import ApplicationServices
import AppKit
import Foundation

final class AccessibilityPermissionManager {
  var isTrusted: Bool {
    AXIsProcessTrusted()
  }

  @discardableResult
  func requestIfNeeded(prompt: Bool) -> Bool {
    guard prompt else { return AXIsProcessTrusted() }
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  func openAccessibilitySettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
      "x-apple.systempreferences:com.apple.Security-Privacy.extension?Privacy_Accessibility",
    ]
    for candidate in candidates {
      guard let url = URL(string: candidate) else { continue }
      if NSWorkspace.shared.open(url) { return }
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
  }
}
