import Foundation

/// Localize app-owned UI. OSM and MapKit proper names remain as provided.
enum L10n {
    static func text(_ key: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: [CVarArg], bundle: Bundle = .main) -> String {
        String(format: text(key, bundle: bundle), locale: Locale.current, arguments: arguments)
    }

    /// Preserve the original named exits for matching station signs.
    /// Keep the existing classification and the exact exit identifier in both languages.
    static func exitLabel(_ reference: String, bundle: Bundle = .main) -> String {
        let hasJapanese = reference.unicodeScalars.contains { $0.value >= 0x3000 }
        return hasJapanese ? reference : format("exit.number", [reference], bundle: bundle)
    }
}
