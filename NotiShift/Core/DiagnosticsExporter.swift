import AppKit
import Foundation

final class DiagnosticsExporter {
  private let profile: CompatibilityProfile
  private let resolver: NotificationCenterProcessResolver
  private let cgInspector = CGWindowInspector()

  init(profile: CompatibilityProfile) {
    self.profile = profile
    self.resolver = NotificationCenterProcessResolver(profile: profile)
  }

  func export() throws -> URL {
    let process = resolver.resolve()
    let windows = cgInspector.snapshots(for: process?.pid)
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let screenDescriptions = NSScreen.screens.map {
      "frame=\(NSStringFromRect($0.frame)) visible=\(NSStringFromRect($0.visibleFrame)) scale=\($0.backingScaleFactor)"
    }.joined(separator: "\n")
    let cgWindowDescriptions = windows.map {
      "pid=\($0.ownerPID) owner=\($0.ownerName) layer=\($0.layer) alpha=\($0.alpha) onscreen=\($0.isOnscreen) bounds=\(NSStringFromRect($0.bounds))"
    }.joined(separator: "\n")

    let content = """
    NotiShift Diagnostics
    =====================
    macOS: \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)
    Profile: \(profile.generation.rawValue)
    AXTrusted: \(AXIsProcessTrusted())
    NotificationCenterPID: \(process?.pid.description ?? "not found")
    NotificationCenterBundleID: \(process?.bundleIdentifier ?? "unknown")
    NotificationCenterName: \(process?.localizedName ?? "unknown")

    Screens
    -------
    \(screenDescriptions)

    CGWindows
    ---------
    \(cgWindowDescriptions)
    """

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("NotiShift-Diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
