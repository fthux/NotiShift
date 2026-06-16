import ApplicationServices
import AppKit
import Foundation

private func notificationCenterAXObserverCallback(
  _: AXObserver,
  _ element: AXUIElement,
  _ notification: CFString,
  _ refcon: UnsafeMutableRawPointer?
) {
  guard let refcon else { return }
  let watcher = Unmanaged<NotificationCenterWatcher>.fromOpaque(refcon).takeUnretainedValue()
  watcher.handleAXNotification(notification as String, element: element)
}

final class NotificationCenterWatcher {
  private let profile: CompatibilityProfile
  private let resolver: NotificationCenterProcessResolver
  private let detector: NotificationBannerDetector
  private let relocator: NotificationRelocator
  private let logger = AppLogger.shared

  private var axObserver: AXObserver?
  private var observedWindowKeys = Set<String>()
  private var currentProcess: NotificationCenterProcess?
  private var pollingTimer: Timer?
  private var workspaceObservers: [NSObjectProtocol] = []

  init(profile: CompatibilityProfile, preferences: NotiShiftPreferences) {
    self.profile = profile
    self.resolver = NotificationCenterProcessResolver(profile: profile)
    self.detector = NotificationBannerDetector(profile: profile)
    self.relocator = NotificationRelocator(detector: detector, preferences: preferences)
  }

  deinit {
    stop()
  }

  func start() {
    stopObserverOnly()
    currentProcess = resolver.resolve()

    guard let process = currentProcess else {
      logger.info("Notification Center not found; polling will retry")
      startPolling()
      installWorkspaceObservers()
      return
    }

    let appElement = AXUIElementCreateApplication(process.pid)
    var observer: AXObserver?
    let result = AXObserverCreate(process.pid, notificationCenterAXObserverCallback, &observer)

    guard result == .success, let observer else {
      logger.error("Failed to create AXObserver result=\(result.nsName)")
      startPolling()
      installWorkspaceObservers()
      return
    }

    axObserver = observer
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    register(kAXWindowCreatedNotification as String, for: appElement, label: "Notification Center app")
    register(AppConstants.childrenChangedNotification, for: appElement, label: "Notification Center app")
    refreshWindowObservers()
    startPolling()
    installWorkspaceObservers()

    logger.info(
      "Notification Center watcher ready pid=\(process.pid) bundle=\(process.bundleIdentifier ?? "unknown") generation=\(profile.generation.rawValue)"
    )
    moveAll()
  }

  func stop() {
    relocator.restore(windows: notificationCenterWindows, reason: "watcher stopped")
    stopObserverOnly()
    pollingTimer?.invalidate()
    pollingTimer = nil
    for observer in workspaceObservers {
      NotificationCenter.default.removeObserver(observer)
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    workspaceObservers.removeAll()
  }

  func moveAll() {
    relocator.move(windows: notificationCenterWindows)
  }

  func moveRepeatedly() {
    let delays: [TimeInterval] = [0.05, 0.12, 0.22, 0.35, 0.55, 0.8, 1.15, 1.6, 2.2]
    for delay in delays {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard let self else { return }
        self.refreshWindowObservers()
        self.moveAll()
      }
    }
  }

  func restart() {
    logger.info("Restarting Notification Center watcher")
    relocator.resetBaseline()
    start()
  }

  fileprivate func handleAXNotification(_ notification: String, element: AXUIElement) {
    logger.debug("Observed \(notification) on \(element.nsSummary())")
    refreshWindowObservers()
    moveAll()
  }

  private var notificationCenterElement: AXUIElement? {
    guard let currentProcess else { return nil }
    return AXUIElementCreateApplication(currentProcess.pid)
  }

  private var notificationCenterWindows: [AXUIElement] {
    notificationCenterElement?.nsAttribute(kAXWindowsAttribute, as: [AXUIElement].self) ?? []
  }

  private func stopObserverOnly() {
    if let axObserver {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }
    axObserver = nil
    observedWindowKeys.removeAll()
    currentProcess = nil
  }

  private func register(_ notification: String, for element: AXUIElement, label: String) {
    guard let axObserver else { return }
    let result = AXObserverAddNotification(
      axObserver,
      element,
      notification as CFString,
      Unmanaged.passUnretained(self).toOpaque()
    )

    switch result {
    case .success, .notificationAlreadyRegistered:
      logger.debug("Registered \(notification) for \(label)")
    case .notificationUnsupported:
      logger.debug("Notification unsupported \(notification) for \(label)")
    default:
      logger.error("Failed to register \(notification) for \(label) result=\(result.nsName)")
    }
  }

  private func refreshWindowObservers() {
    for window in notificationCenterWindows {
      let key = observerKey(for: window)
      guard observedWindowKeys.insert(key).inserted else { continue }
      register(AppConstants.childrenChangedNotification, for: window, label: "Notification Center window")
      register(kAXCreatedNotification as String, for: window, label: "Notification Center window")
      register(
        kAXUIElementDestroyedNotification as String,
        for: window,
        label: "Notification Center window"
      )
    }
  }

  private func observerKey(for window: AXUIElement) -> String {
    let role = window.nsAttribute(kAXRoleAttribute, as: String.self) ?? "?"
    let subrole = window.nsAttribute(kAXSubroleAttribute, as: String.self) ?? "?"
    let position = window.nsPoint(for: kAXPositionAttribute) ?? .zero
    let size = window.nsSize(for: kAXSizeAttribute) ?? .zero
    return "\(role)|\(subrole)|\(position.x)|\(position.y)|\(size.width)|\(size.height)"
  }

  private func startPolling() {
    guard profile.enablePollingFallback, pollingTimer == nil else { return }
    pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
      guard let self else { return }
      if self.currentProcess == nil {
        self.currentProcess = self.resolver.resolve()
      }
      self.refreshWindowObservers()
      self.moveAll()
    }
    RunLoop.current.add(pollingTimer!, forMode: .common)
  }

  private func installWorkspaceObservers() {
    guard workspaceObservers.isEmpty else { return }

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.didLaunchApplicationNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.restartIfNeeded()
      }
    )
    workspaceObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.restartIfNeeded()
      }
    )
    workspaceObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.restart()
      }
    )
    workspaceObservers.append(
      workspaceCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.moveAll()
      }
    )
    workspaceObservers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.relocator.resetBaseline()
        self?.moveAll()
      }
    )
  }

  private func restartIfNeeded() {
    let resolved = resolver.resolve()
    if resolved?.pid != currentProcess?.pid {
      restart()
    }
  }
}
