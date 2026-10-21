import Foundation

/// One gate for fixture arguments. Release builds always use real adapters.
struct UITestConfiguration: Sendable {
    static let current = UITestConfiguration()
    let arguments: [String]
    let enabled: Bool
    private init() {
        #if DEBUG
        let values = ProcessInfo.processInfo.arguments
        enabled = values.contains("--ui-testing")
        arguments = enabled ? values : []
        #else
        enabled = false
        arguments = []
        #endif
    }
    func contains(_ flag: String) -> Bool { enabled && arguments.contains(flag) }
}
