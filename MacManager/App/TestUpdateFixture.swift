import Foundation
import MacManagerCore

#if DEBUG
struct TestUpdateFixture: Sendable {
    enum Mode: Equatable, Sendable {
        case noRelease
        case current
        case available
        case failed
    }

    let mode: Mode
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.9"

    init(arguments: [String]) {
        if arguments.contains("--update-available") {
            mode = .available
        } else if arguments.contains("--update-current") {
            mode = .current
        } else if arguments.contains("--update-failure") {
            mode = .failed
        } else {
            mode = .noRelease
        }
    }

    func fetch(etag: String?) async throws -> UpdateCheckPayload {
        if mode == .failed { throw UpdateCheckFailure(.timeout) }
        if etag != nil { return .notModified(etag: "\"ui-test\"") }
        switch mode {
        case .noRelease:
            return .noPublicRelease(etag: "\"ui-test\"")
        case .current:
            return .release(release(version: currentVersion), etag: "\"ui-test\"")
        case .available:
            return .release(release(version: "0.9.0"), etag: "\"ui-test\"")
        case .failed:
            throw UpdateCheckFailure(.timeout)
        }
    }

    private func release(version: String) -> UpdateRelease {
        let semanticVersion = SemanticVersion.parse(version)!
        let tag = semanticVersion.tag
        return UpdateRelease(
            version: semanticVersion,
            tag: tag,
            pageURL: URL(string: "https://github.com/MrDeex1k/MacManager/releases/tag/\(tag)")!,
            assetName: "MacManager-\(tag)-arm64.dmg"
        )
    }
}
#endif
