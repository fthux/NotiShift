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
    case .topLeft: "Top Left"
    case .topCenter: "Top Center"
    case .topRight: "Top Right"
    case .middleLeft: "Middle Left"
    case .center: "Center"
    case .middleRight: "Middle Right"
    case .bottomLeft: "Bottom Left"
    case .bottomCenter: "Bottom Center"
    case .bottomRight: "Bottom Right"
    }
  }
}
