import Foundation

struct AppStrings {
    let languageCode: String

    private var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let localized = Bundle(path: path) else { return .main }
        return localized
    }

    func callAsFunction(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }
}
