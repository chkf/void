import Foundation

enum HostLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    static let key = "void.hostLanguage"
    var displayName: String { self == .chinese ? "简体中文" : "English" }
    static var current: Self {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .chinese
    }

    static func text(_ key: String) -> String {
        let path = Bundle.main.path(forResource: current.rawValue, ofType: "lproj")
        return path.flatMap(Bundle.init(path:))?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    static func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: current.rawValue), arguments: values)
    }
}
