import AppKit
import Foundation

protocol OnboardingWindowControllerDelegate: AnyObject {
  func onboardingDidRequestAccessibilitySettings()
  func onboardingDidRequestPreferences()
  func onboardingDidFinish()
}

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
  weak var onboardingDelegate: OnboardingWindowControllerDelegate?

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = L10n.text("onboarding.title")
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    window.contentView = makeContentView()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    window?.center()
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    onboardingDelegate?.onboardingDidFinish()
  }

  private func makeContentView() -> NSView {
    let contentView = NSView()

    let stack = NSStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)

    let titleLabel = NSTextField(labelWithString: L10n.text("onboarding.heading"))
    titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)

    let bodyLabel = NSTextField(wrappingLabelWithString: L10n.text("onboarding.body"))
    bodyLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    bodyLabel.maximumNumberOfLines = 0
    bodyLabel.preferredMaxLayoutWidth = 400

    let stepsLabel = NSTextField(wrappingLabelWithString: L10n.text("onboarding.steps"))
    stepsLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    stepsLabel.textColor = .secondaryLabelColor
    stepsLabel.maximumNumberOfLines = 0
    stepsLabel.preferredMaxLayoutWidth = 400

    let buttonRow = NSStackView()
    buttonRow.orientation = .horizontal
    buttonRow.alignment = .centerY
    buttonRow.spacing = 10

    let openSettingsButton = NSButton(
      title: L10n.text("button.openAccessibilitySettings"),
      target: self,
      action: #selector(openAccessibilitySettings)
    )
    let preferencesButton = NSButton(
      title: L10n.text("button.openPreferences"),
      target: self,
      action: #selector(openPreferences)
    )
    let continueButton = NSButton(
      title: L10n.text("button.continue"),
      target: self,
      action: #selector(finish)
    )
    continueButton.keyEquivalent = "\r"

    buttonRow.addArrangedSubview(openSettingsButton)
    buttonRow.addArrangedSubview(preferencesButton)
    buttonRow.addArrangedSubview(continueButton)

    stack.addArrangedSubview(titleLabel)
    stack.addArrangedSubview(bodyLabel)
    stack.addArrangedSubview(stepsLabel)
    stack.addArrangedSubview(buttonRow)
    contentView.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: contentView.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
    ])

    return contentView
  }

  @objc private func openAccessibilitySettings() {
    onboardingDelegate?.onboardingDidRequestAccessibilitySettings()
  }

  @objc private func openPreferences() {
    onboardingDelegate?.onboardingDidRequestPreferences()
    finish()
  }

  @objc private func finish() {
    onboardingDelegate?.onboardingDidFinish()
    close()
  }
}
