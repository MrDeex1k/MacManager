import Foundation
import Observation
import OSLog

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
    private struct IndexedEntry {
        let entry: LauncherEntry
        let fields: SearchFields
        let favorite: Bool
    }
    private let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "launcher")
    private var source: [LauncherEntry] = []
    private var customizations: [String: LauncherCustomization] = [:]
    private var index: [IndexedEntry] = []

    public init() {}
    public func search(_ query: String, entries: [LauncherEntry], limit: Int = 40, preferences: LauncherPreferences = .init()) throws -> [LauncherEntry] {
        let interval = signposter.beginInterval("Rank", id: signposter.makeSignpostID())
        defer { signposter.endInterval("Rank", interval) }
        if source != entries || customizations != preferences.items {
            var prepared: [IndexedEntry] = []
            var seen = Set<String>()
            for entry in entries {
                try Task.checkCancellation()
                let custom = preferences.items[entry.id]
                guard custom?.hidden != true, seen.insert(entry.id).inserted else { continue }
                var fields = entry.fields
                // Preserve the existing alias/favorite ordering while optimizing preparation.
                if let alias = custom?.alias, !alias.isEmpty { fields.append(.name(alias)) }
                prepared.append(IndexedEntry(entry: entry, fields: fields, favorite: custom?.favorite == true))
            }
            source = entries; customizations = preferences.items; index = prepared
        }
        let folded = FuzzyMatch.Query(String(query.prefix(256)).trimmingCharacters(in: .whitespacesAndNewlines))
        var ranked: [(LauncherEntry, Int)] = []
        for item in index {
            try Task.checkCancellation()
            guard let score = SearchRelevance.quality(folded, fields: item.fields) else { continue }
            ranked.append((item.entry, score + (item.favorite ? 1_000_000 : 0)))
        }
        let locale = Locale(identifier: "en_US_POSIX")
        return ranked.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let comparison = $0.0.title.compare($1.0.title, options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            return comparison == .orderedSame ? $0.0.id < $1.0.id : comparison == .orderedAscending
        }.prefix(max(0, limit)).map(\.0)
    }
}

@MainActor @Observable
public final class LauncherSearchModel {
    public private(set) var results: [LauncherEntry] = []
    public private(set) var isLoading = false
    public private(set) var isSearching = false
    public private(set) var resultsAreCurrent = false
    public private(set) var failed = false
    public private(set) var query = ""
    public var selectedID: String?
    public var selected: LauncherEntry? {
        guard resultsAreCurrent else { return nil }
        return results.first { $0.id == selectedID }
    }
    @ObservationIgnored private let engine = LauncherSearchEngine()
    @ObservationIgnored private let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "launcher")
    @ObservationIgnored private var providerFailed = false
    @ObservationIgnored private var catalog: [LauncherEntry] = []
    @ObservationIgnored private var providerEntries: [LauncherEntry] = []
    @ObservationIgnored private var catalogLanguage: String?
    @ObservationIgnored private var loadedAt: ContinuousClock.Instant?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var searchGeneration = 0
    public var preferences = LauncherPreferences()
    public var onlyAdditionalResults = false {
        didSet {
            if oldValue != onlyAdditionalResults { cancelSearch(clear: true) }
        }
    }
    @ObservationIgnored public var additionalResults: (@MainActor (String) async throws -> [LauncherEntry])?
    public init() {}

    public func invalidateCatalog() { loadedAt = nil }

    public func reconcileApplications(replacements: [String: LauncherEntry], removed: Set<String>) {
        func reconcile(_ entries: [LauncherEntry]) -> [LauncherEntry] {
            entries.filter { !removed.contains($0.id) }.map { replacements[$0.id] ?? $0 }
        }
        catalog = reconcile(catalog)
        providerEntries = reconcile(providerEntries)
        loadedAt = nil
    }

    public func load(providers: [any LauncherProvider], language: String, commands: [LauncherEntry]) {
        cancel()
        if catalogLanguage != language {
            providerEntries = []; loadedAt = nil; providerFailed = false
        }
        catalogLanguage = language
        catalog = commands + providerEntries
        failed = providerFailed
        search("")
        if let loadedAt, loadedAt.duration(to: .now) < .seconds(60) { return }
        isLoading = true
        let token = generation
        loadTask = Task { [weak self] in
            let batches = await withTaskGroup(of: (Int, [LauncherEntry], Bool).self) { group in
                for (index, provider) in providers.enumerated() {
                    group.addTask {
                        do { return (index, try await provider.entries(language: language), false) }
                        catch { return (index, [], !(error is CancellationError)) }
                    }
                }
                var result: [(Int, [LauncherEntry], Bool)] = []
                for await batch in group { result.append(batch) }
                return result.sorted { $0.0 < $1.0 }
            }
            guard let self, token == self.generation, !Task.isCancelled else { return }
            self.providerEntries = batches.flatMap { $0.1 }
            let catalog = commands + self.providerEntries
            let changed = self.catalog != catalog
            self.catalog = catalog
            self.providerFailed = batches.contains { $0.2 }
            self.failed = self.providerFailed
            self.loadedAt = self.providerFailed ? nil : .now
            self.isLoading = false
            self.loadTask = nil
            if changed { self.search(self.query) }
        }
    }

    public func search(_ text: String) {
        failed = providerFailed
        query = String(text.prefix(256))
        cancelSearch(clear: false)
        isSearching = true
        let token = searchGeneration
        let previous = selectedID
        let privateMode = onlyAdditionalResults
        let catalog = privateMode ? [] : catalog, query = query, preferences = preferences, additionalResults = additionalResults
        let interval = signposter.beginInterval("Search", id: signposter.makeSignpostID())
        let signposter = signposter
        searchTask = Task { [weak self, engine] in
            defer { signposter.endInterval("Search", interval) }
            do {
                let matches = try await engine.search(query, entries: catalog, preferences: preferences)
                guard let self, token == self.searchGeneration, !Task.isCancelled else { return }
                // Keep the existing rows until their replacement is ready, but never execute them.
                if !privateMode && (!matches.isEmpty || additionalResults == nil) {
                    self.publish(matches, selected: previous)
                }
                if let additionalResults {
                    let extra = try await additionalResults(query)
                    guard token == self.searchGeneration, !Task.isCancelled else { return }
                    let calculators = extra.filter { $0.id == "calculator:result" }
                    let others = extra.filter { $0.id != "calculator:result" }
                    // Reserve space for files instead of dropping every file behind 40 app hits.
                    let appLimit = max(0, 40 - calculators.count - others.count)
                    let combined = Array((calculators + matches.prefix(appLimit) + others).prefix(40))
                    self.publish(combined, selected: calculators.first?.id ?? self.selectedID ?? previous)
                }
                self.isSearching = false
            } catch {
                guard let self, token == self.searchGeneration, !Task.isCancelled else { return }
                self.isSearching = false
                if !(error is CancellationError) { self.failed = true }
                if !self.resultsAreCurrent { self.publish([], selected: nil) }
            }
        }
    }

    public func canPerform(_ entry: LauncherEntry) -> Bool {
        resultsAreCurrent && results.contains(entry)
    }

    private func publish(_ entries: [LauncherEntry], selected: String?) {
        if results != entries { results = entries }
        selectedID = selected.flatMap { id in entries.contains { $0.id == id } ? id : nil } ?? entries.first?.id
        resultsAreCurrent = true
    }

    public func moveSelection(_ delta: Int) {
        guard resultsAreCurrent, !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(max(index + delta, 0), results.count - 1)].id
    }

    private func cancelSearch(clear: Bool) {
        searchGeneration += 1
        searchTask?.cancel(); searchTask = nil
        resultsAreCurrent = false; isSearching = false
        if clear { results = []; selectedID = nil }
    }

    public func cancel() {
        generation += 1
        loadTask?.cancel(); loadTask = nil
        cancelSearch(clear: true)
        query = ""; isLoading = false
        // The non-private application catalog survives closing the palette.
    }
}
