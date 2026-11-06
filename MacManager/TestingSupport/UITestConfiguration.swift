import Foundation

/// One gate for fixture arguments. Release builds always use real adapters.
struct UITestConfiguration: Sendable {
    static let current = UITestConfiguration()
    let arguments: [String]
    let enabled: Bool
    #if DEBUG
    let preferencesSuite: String?
    #endif
    /// Enables fixtures only on an explicit Debug launch and validates the test domain suffix.
    private init() {
        #if DEBUG
        let values = ProcessInfo.processInfo.arguments
        enabled = values.contains("--ui-testing")
        arguments = enabled ? values : []
        if enabled {
            let fixtureID = ProcessInfo.processInfo.environment["MM_UI_TEST_ID"]
            let id = fixtureID.flatMap {
                $0.count == 32 && $0.allSatisfy { $0.isASCII && $0.isHexDigit } ? $0 : nil
            } ?? UUID().uuidString
            preferencesSuite = "dev.macmanager.MacManager.UITests.\(id)"
        } else {
            preferencesSuite = nil
        }
        #else
        enabled = false
        arguments = []
        #endif
    }
    func contains(_ flag: String) -> Bool { enabled && arguments.contains(flag) }
}
