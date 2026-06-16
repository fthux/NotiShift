import Foundation

enum PreferencesKey {
  static let selectedPosition = "selectedPosition"
  static let isEnabled = "isEnabled"
  static let debugLoggingEnabled = "debugLoggingEnabled"
  static let selectedLanguage = "selectedLanguage"
  static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
}

enum AppLanguage: String, CaseIterable {
  case system
  case english
  case simplifiedChinese

  var displayName: String {
    switch self {
    case .system: "System"
    case .english: "English"
    case .simplifiedChinese: "简体中文"
    }
  }
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

  var selectedLanguage: AppLanguage {
    get {
      defaults.string(forKey: PreferencesKey.selectedLanguage)
        .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
    set {
      defaults.set(newValue.rawValue, forKey: PreferencesKey.selectedLanguage)
    }
  }

  var automaticallyCheckForUpdates: Bool {
    get {
      if defaults.object(forKey: PreferencesKey.automaticallyCheckForUpdates) == nil { return true }
      return defaults.bool(forKey: PreferencesKey.automaticallyCheckForUpdates)
    }
    set {
      defaults.set(newValue, forKey: PreferencesKey.automaticallyCheckForUpdates)
    }
  }
}
