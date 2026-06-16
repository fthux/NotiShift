import Foundation

enum L10n {
  static func text(_ key: String) -> String {
    activeBundle.localizedString(forKey: key, value: nil, table: nil)
  }

  private static var activeBundle: Bundle {
    let rawValue = UserDefaults.standard.string(forKey: PreferencesKey.selectedLanguage)
    let language = rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .system
    guard
      let localization = language.localizationIdentifier,
      let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else {
      return .main
    }
    return bundle
  }
}

extension AppLanguage {
  var localizationIdentifier: String? {
    switch self {
    case .system: nil
    case .english: "en"
    case .simplifiedChinese: "zh-Hans"
    }
  }
}
