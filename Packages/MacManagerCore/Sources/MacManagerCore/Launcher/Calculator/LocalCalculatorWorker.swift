import Foundation

public actor LocalCalculatorWorker {
    public init() {}
    public func result(_ query: String, context: LocalCalculator.Context) throws -> LauncherEntry? {
        try Task.checkCancellation()
        let result = LocalCalculator.result(query, context: context)
        try Task.checkCancellation()
        return result
    }
}
