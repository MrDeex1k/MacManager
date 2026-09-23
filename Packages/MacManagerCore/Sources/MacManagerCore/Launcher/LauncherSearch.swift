import Foundation
import Observation

public enum LauncherAction: Hashable, Sendable, Codable {
    case clipboard(UUID)
    case file(URL)
    case copy(String)
    case application(URL)
    case section(String)
    case systemSettings(URL)
}

public struct LauncherEntry: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let action: LauncherAction
    public let alternateNames: [String]
    public let bundleID: String?
    public init(id: String, title: String, subtitle: String = "", symbol: String = "app",
                action: LauncherAction, alternateNames: [String] = [], bundleID: String? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.symbol = symbol
        self.action = action; self.alternateNames = alternateNames; self.bundleID = bundleID
    }
    var fields: SearchFields {
        var result = SearchFields([.name(title)] + alternateNames.map { .translation($0) })
        if let bundleID { result.append(.technical(bundleID)) }
        return result
    }
}

public protocol LauncherProvider: Sendable {
    func entries(language: String) async throws -> [LauncherEntry]
}

public actor LauncherSearchEngine {
    public init() {}
    public func search(_ query: String, entries: [LauncherEntry], limit: Int = 40, preferences: LauncherPreferences = .init()) throws -> [LauncherEntry] {
        let folded = FuzzyMatch.Query(String(query.prefix(256)).trimmingCharacters(in: .whitespacesAndNewlines))
        var ranked: [(LauncherEntry, Int)] = []
        var seen = Set<String>()
        for entry in entries {
            try Task.checkCancellation()
            let custom = preferences.items[entry.id]
            guard custom?.hidden != true, seen.insert(entry.id).inserted else { continue }
            var fields = entry.fields
            if let alias = custom?.alias, !alias.isEmpty { fields.append(.name(alias)) }
            guard let score = SearchRelevance.quality(folded, fields: fields) else { continue }
            ranked.append((entry, score + (custom?.favorite == true ? 1_000_000 : 0)))
        }
        return ranked.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let comparison = $0.0.title.compare($1.0.title, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return comparison == .orderedSame ? $0.0.id < $1.0.id : comparison == .orderedAscending
        }.prefix(max(0, limit)).map(\.0)
    }
}

@MainActor @Observable
public final class LauncherSearchModel {
    public private(set) var results: [LauncherEntry] = []
    public private(set) var isLoading = false
    public private(set) var failed = false
    public private(set) var query = ""
    public var selectedID: String?
    public var selected: LauncherEntry? { results.first { $0.id == selectedID } }
    @ObservationIgnored private let engine = LauncherSearchEngine()
    @ObservationIgnored private var providerFailed = false
    @ObservationIgnored private var catalog: [LauncherEntry] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var searchGeneration = 0
    public var preferences = LauncherPreferences()
    public var onlyAdditionalResults = false
    @ObservationIgnored public var additionalResults: (@MainActor (String) async throws -> [LauncherEntry])?
    public init() {}

    public func load(providers: [any LauncherProvider], language: String, commands: [LauncherEntry]) {
        cancel()
        catalog = commands
        isLoading = true; failed = false; providerFailed = false
        search("")
        let token = generation
        loadTask = Task { [weak self] in
            var found = commands
            var hasFailure = false
            for provider in providers {
                do { found += try await provider.entries(language: language) }
                catch is CancellationError { return }
                catch { hasFailure = true }
            }
            guard let self, token == self.generation, !Task.isCancelled else { return }
            self.catalog = found; self.isLoading = false; self.providerFailed = hasFailure; self.failed = hasFailure
            self.search(self.query)
        }
    }
    public func search(_ text: String) {
        failed = providerFailed
        query = String(text.prefix(256))
        searchTask?.cancel(); searchGeneration += 1
        let token = searchGeneration
        // Never execute a result belonging to an earlier query while the next search runs.
        results = []; selectedID = nil
        let catalog = onlyAdditionalResults ? [] : catalog, query = query, preferences = preferences, additionalResults = additionalResults
        searchTask = Task { [weak self, engine] in
            do {
                let matches = try await engine.search(query, entries: catalog, preferences: preferences)
                guard let self, token == self.searchGeneration, !Task.isCancelled else { return }
                self.results = matches; self.selectedID = matches.first?.id
                guard let additionalResults else { return }
                let extra = try await additionalResults(query)
                guard token == self.searchGeneration, !Task.isCancelled else { return }
                let previous = self.selectedID
                self.results = Array((extra.filter { $0.id == "calculator:result" } + matches + extra.filter { $0.id != "calculator:result" }).prefix(40))
                self.selectedID = previous.flatMap { id in self.results.contains { $0.id == id } ? id : nil } ?? self.results.first?.id
                if extra.first?.id == "calculator:result" { self.selectedID = extra.first?.id }
            } catch {
                if let self, token == self.searchGeneration, !Task.isCancelled { self.failed = true }
            }
        }
    }
    public func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(index + delta, 0), results.count - 1)].id
    }
    public func cancel() {
        generation += 1; searchGeneration += 1
        searchTask?.cancel(); loadTask?.cancel()
        searchTask = nil; loadTask = nil
        results = []; catalog = []; query = ""; selectedID = nil; isLoading = false
    }
}
