import Foundation

enum PreferencesKey {
  static let selectedPosition = "selectedPosition"
  static let isEnabled = "isEnabled"
  static let debugLoggingEnabled = "debugLoggingEnabled"
}

final class NotiShiftPreferences {
  static let shared = NotiShiftPreferences()

  private let defaults = UserDefaults.standard

  var selectedPosition: NotificationPosition {
    get {
      defaults.string(forKey: PreferencesKey.selectedPosition)
        .flatMap(NotificationPosition.init(rawValue:)) ?? .topCenter
    }
    set {
      defaults.set(newValue.rawValue, forKey: PreferencesKey.selectedPosition)
    }
  }

  var isEnabled: Bool {
    get {
      if defaults.object(forKey: PreferencesKey.isEnabled) == nil { return true }
      return defaults.bool(forKey: PreferencesKey.isEnabled)
    }
    set {
      defaults.set(newValue, forKey: PreferencesKey.isEnabled)
    }
  }

  var debugLoggingEnabled: Bool {
    get { defaults.bool(forKey: PreferencesKey.debugLoggingEnabled) }
    set { defaults.set(newValue, forKey: PreferencesKey.debugLoggingEnabled) }
  }
}
