import AppKit
import Foundation

protocol MenuBarControllerDelegate: AnyObject {
  func menuBarControllerDidToggleEnabled()
  func menuBarControllerDidSelectPosition()
  func menuBarControllerDidRequestPreferences()
}

final class MenuBarController {
  weak var delegate: MenuBarControllerDelegate?

  private let preferences: NotiShiftPreferences
  private var statusItem: NSStatusItem?

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
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    NSColor.black.setFill()

    let upperBlock = NSBezierPath(
      roundedRect: NSRect(x: 1.8, y: 7.7, width: 8.6, height: 8.2),
      xRadius: 2.3,
      yRadius: 2.3
    )
    upperBlock.fill()

    let lowerBlock = NSBezierPath(
      roundedRect: NSRect(x: 7.6, y: 2.1, width: 8.6, height: 8.1),
      xRadius: 2.3,
      yRadius: 2.3
    )
    lowerBlock.fill()

    NSGraphicsContext.current?.compositingOperation = .clear
    NSBezierPath(ovalIn: NSRect(x: 7.9, y: 7.0, width: 3.7, height: 3.7)).fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver

    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: 12.6, y: 11.7, width: 3.2, height: 3.2)).fill()
    image.unlockFocus()
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

  @objc private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}
