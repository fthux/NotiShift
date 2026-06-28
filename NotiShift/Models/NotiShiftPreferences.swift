import Foundation

enum PreferencesKey {
  static let selectedPosition = "selectedPosition"
  static let isEnabled = "isEnabled"
  static let debugLoggingEnabled = "debugLoggingEnabled"
  static let selectedLanguage = "selectedLanguage"
  static let selectedTheme = "selectedTheme"
  // static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
  // static let lastUpdateCheckAt = "lastUpdateCheckAt"
  static let hasCompletedOnboarding = "hasCompletedOnboarding"
  static let lastOnboardingPromptVersion = "lastOnboardingPromptVersion"
}

enum AppLanguage: String, CaseIterable {
  case system
  case english
  case simplifiedChinese

  var displayName: String {
    switch self {
    case .system: L10n.text("language.system")
    case .english: "English"
    case .simplifiedChinese: "简体中文"
    }
  }
}

enum AppTheme: String, CaseIterable {
  case system
  case light
  case dark

  var displayName: String {
    switch self {
    case .system: L10n.text("theme.system")
    case .light: L10n.text("theme.light")
    case .dark: L10n.text("theme.dark")
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

  var selectedTheme: AppTheme {
    get {
      defaults.string(forKey: PreferencesKey.selectedTheme)
        .flatMap(AppTheme.init(rawValue:)) ?? .system
    }
    set {
      defaults.set(newValue.rawValue, forKey: PreferencesKey.selectedTheme)
    }
  }

  // var automaticallyCheckForUpdates: Bool {
  //   get {
  //     if defaults.object(forKey: PreferencesKey.automaticallyCheckForUpdates) == nil { return true }
  //     return defaults.bool(forKey: PreferencesKey.automaticallyCheckForUpdates)
  //   }
  //   set {
  //     defaults.set(newValue, forKey: PreferencesKey.automaticallyCheckForUpdates)
  //   }
  // }
  //
  // var lastUpdateCheckAt: Date? {
  //   get { defaults.object(forKey: PreferencesKey.lastUpdateCheckAt) as? Date }
  //   set { defaults.set(newValue, forKey: PreferencesKey.lastUpdateCheckAt) }
  // }

  var hasCompletedOnboarding: Bool {
    get { defaults.bool(forKey: PreferencesKey.hasCompletedOnboarding) }
    set { defaults.set(newValue, forKey: PreferencesKey.hasCompletedOnboarding) }
  }

  var lastOnboardingPromptVersion: String? {
    get { defaults.string(forKey: PreferencesKey.lastOnboardingPromptVersion) }
    set { defaults.set(newValue, forKey: PreferencesKey.lastOnboardingPromptVersion) }
  }
}
