import AppKit
import Foundation

protocol MenuBarControllerDelegate: AnyObject {
  func menuBarControllerDidToggleEnabled()
  func menuBarControllerDidSelectPosition()
  func menuBarControllerDidRequestPreferences()
  func menuBarControllerDidRequestAccessibilitySettings()
  func menuBarControllerDidRequestNotificationSettings() -> Bool
}

final class MenuBarController {
  weak var delegate: MenuBarControllerDelegate?

  private let preferences: NotiShiftPreferences
  private var statusItem: NSStatusItem?
  var accessibilityPermissionGranted = false
  var notificationPermissionStatus: NotificationPermissionStatus?

  init(preferences: NotiShiftPreferences) {
    self.preferences = preferences
  }

  func install() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem?.button {
      button.image = menuBarImage()
      button.image?.size = NSSize(width: 18, height: 18)
      button.imagePosition = .imageOnly
    }
    rebuildMenu()
  }

  private func menuBarImage() -> NSImage {
    let image = NSImage(named: "NotiShiftMenuBarIcon") ?? NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil) ?? NSImage()
    image.isTemplate = true
    return image
  }

  func rebuildMenu() {
    let menu = NSMenu()

    let enabledItem = NSMenuItem(title: L10n.text("menu.enabled"), action: #selector(toggleEnabled(_:)), keyEquivalent: "")
    enabledItem.target = self
    enabledItem.state = preferences.isEnabled ? .on : .off
    menu.addItem(enabledItem)

    let positionItem = NSMenuItem(title: L10n.text("menu.position"), action: nil, keyEquivalent: "")
    let positionMenu = NSMenu()
    for position in NotificationPosition.allCases {
      let item = NSMenuItem(title: position.displayName, action: #selector(selectPosition(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = position
      item.state = preferences.selectedPosition == position ? .on : .off
      positionMenu.addItem(item)
    }
    positionItem.submenu = positionMenu
    menu.addItem(positionItem)

    menu.addItem(.separator())

    if accessibilityPermissionGranted {
      let item = NSMenuItem(title: L10n.text("menu.accessibilityGranted"), action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    } else {
      let item = NSMenuItem(title: L10n.text("menu.openAccessibilitySettings"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }

    if notificationPermissionStatus == .granted {
      let item = NSMenuItem(title: L10n.text("menu.notificationGranted"), action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
    } else {
      let item = NSMenuItem(title: L10n.text("menu.openNotificationSettings"), action: #selector(openNotificationSettings), keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }

    menu.addItem(.separator())

    let preferencesItem = NSMenuItem(title: L10n.text("menu.preferences"), action: #selector(showPreferences), keyEquivalent: ",")
    preferencesItem.target = self
    menu.addItem(preferencesItem)

    let aboutItem = NSMenuItem(title: L10n.text("menu.about"), action: #selector(showAbout), keyEquivalent: "")
    aboutItem.target = self
    menu.addItem(aboutItem)

    let quitItem = NSMenuItem(title: L10n.text("menu.quit"), action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem?.menu = menu
  }

  @objc private func toggleEnabled(_ sender: NSMenuItem) {
    preferences.isEnabled.toggle()
    sender.state = preferences.isEnabled ? .on : .off
    delegate?.menuBarControllerDidToggleEnabled()
    rebuildMenu()
  }

  @objc private func selectPosition(_ sender: NSMenuItem) {
    guard let position = sender.representedObject as? NotificationPosition else { return }
    preferences.selectedPosition = position
    delegate?.menuBarControllerDidSelectPosition()
    rebuildMenu()
  }

  @objc private func showPreferences() {
    delegate?.menuBarControllerDidRequestPreferences()
  }

  @objc private func openAccessibilitySettings() {
    delegate?.menuBarControllerDidRequestAccessibilitySettings()
  }

  @objc private func openNotificationSettings() {
    _ = delegate?.menuBarControllerDidRequestNotificationSettings()
  }

  @objc private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}
