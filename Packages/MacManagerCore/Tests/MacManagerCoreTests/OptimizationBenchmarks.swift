import Foundation
import Testing
@testable import MacManagerCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_BENCHMARKS"] == "1", "Run explicitly with MM_BENCHMARKS=1 in Release"))
func launcherRankingBenchmark() async throws {
    let engine = LauncherSearchEngine()
    for count in [200, 1_000, 5_000] {
        let entries = (0..<count).map {
            LauncherEntry(id: "app:\($0)", title: "Application \($0)", action: .section("overview"))
        }
        var times: [Double] = []
        let clock = ContinuousClock()
        for index in 0..<180 {
            let start = clock.now
            _ = try await engine.search(["app", "application", "17", "missing"][index % 4], entries: entries)
            let elapsed = start.duration(to: clock.now).components
            times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        times.sort()
        print("Ranking \(count): p50=\(times[90])ms p95=\(times[171])ms")
    }
}
