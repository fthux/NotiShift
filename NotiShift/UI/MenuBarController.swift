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
      button.imagePosition = .imageOnly
    }
    rebuildMenu()
  }

  private func menuBarImage() -> NSImage {
    if #available(macOS 11.0, *),
      let image = NSImage(systemSymbolName: "bell", accessibilityDescription: "NotiShift")
    {
      image.isTemplate = true
      image.size = NSSize(width: 18, height: 18)
      return image
    }

    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    NSColor.black.setStroke()
    NSColor.black.setFill()

    let bell = NSBezierPath()
    bell.lineWidth = 1.7
    bell.move(to: NSPoint(x: 5.0, y: 6.4))
    bell.curve(
      to: NSPoint(x: 13.0, y: 6.4),
      controlPoint1: NSPoint(x: 5.1, y: 11.4),
      controlPoint2: NSPoint(x: 12.9, y: 11.4)
    )
    bell.line(to: NSPoint(x: 14.2, y: 5.0))
    bell.line(to: NSPoint(x: 3.8, y: 5.0))
    bell.close()
    bell.stroke()

    NSBezierPath(ovalIn: NSRect(x: 7.2, y: 2.3, width: 3.6, height: 3.0)).fill()
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  func rebuildMenu() {
    let menu = NSMenu()

    let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
    enabledItem.target = self
    enabledItem.state = preferences.isEnabled ? .on : .off
    menu.addItem(enabledItem)

    let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
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
    let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
    preferencesItem.target = self
    menu.addItem(preferencesItem)

    let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
    aboutItem.target = self
    menu.addItem(aboutItem)

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
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
