import Foundation
import Testing
@testable import MacManagerCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["MM_BENCHMARKS"] == "1", "Run explicitly with MM_BENCHMARKS=1 in Release"))
func launcherRankingBenchmark() async throws {
    for count in [200, 1_000, 5_000] {
        let entries = (0..<count).map {
            LauncherEntry(id: "app:\($0)", title: "Application \($0)", action: .section("overview"))
        }
        let engine = LauncherSearchEngine()
        let clock = ContinuousClock()
        let cold = clock.now
        _ = try await engine.search("app", entries: entries, catalogRevision: 1)
        print("Cold index \(count): \(milliseconds(cold.duration(to: clock.now)))ms")
        var times: [Double] = []
        for index in 0..<180 {
            let start = clock.now
            _ = try await engine.search(["app", "application", "17", "missing"][index % 4], entries: entries, catalogRevision: 1)
            let elapsed = start.duration(to: clock.now).components
            times.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        times.sort()
        print("Warm stable revision \(count): p50=\(times[90])ms p95=\(times[171])ms")
        var options = LauncherPreferences()
        var item = LauncherCustomization(entry: entries[0]); item.alias = "Personal alias"; item.favorite = true
        options.items[item.entry.id] = item
        let personalized = clock.now
        let results = try await engine.search("Personal alias", entries: entries, preferences: options, catalogRevision: 2)
        #expect(results.first?.id == item.entry.id)
        print("Personalization rebuild \(count): \(milliseconds(personalized.duration(to: clock.now)))ms")
    }
}

private func milliseconds(_ duration: Duration) -> Double {
    let value = duration.components
    return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
}
