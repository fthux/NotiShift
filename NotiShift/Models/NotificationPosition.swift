import Foundation

enum NotificationPosition: String, CaseIterable, Codable {
  case topLeft
  case topCenter
  case topRight
  case middleLeft
  case center
  case middleRight
  case bottomLeft
  case bottomCenter
  case bottomRight

  var displayName: String {
    switch self {
    case .topLeft: L10n.text("position.topLeft")
    case .topCenter: L10n.text("position.topCenter")
    case .topRight: L10n.text("position.topRight")
    case .middleLeft: L10n.text("position.middleLeft")
    case .center: L10n.text("position.center")
    case .middleRight: L10n.text("position.middleRight")
    case .bottomLeft: L10n.text("position.bottomLeft")
    case .bottomCenter: L10n.text("position.bottomCenter")
    case .bottomRight: L10n.text("position.bottomRight")
    }
  }
}
