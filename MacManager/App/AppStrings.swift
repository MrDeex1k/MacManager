import Foundation

struct AppStrings {
    let languageCode: String

    private static let bundles = Dictionary(uniqueKeysWithValues: Bundle.main.localizations.compactMap { code in
        Bundle.main.url(forResource: code, withExtension: "lproj")
            .flatMap(Bundle.init(url:))
            .map { (code, $0) }
    })

    /// Looks up a key in the cached bundle for the selected language, falling back to the main bundle.
    func callAsFunction(_ key: String) -> String {
        let bundle = Self.bundles[languageCode] ?? .main
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }
}
