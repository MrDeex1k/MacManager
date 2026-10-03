// Adapted from Tinycast FileSearchService/Query, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Modified 2026-09-23: explicit roots only, serial bounded queries, no recent-file history.
// Modified 2026-10-03: asynchronous gathering with cancellation and a bounded timeout.
import CoreServices
import Foundation

public enum LauncherFileFilter: String, CaseIterable, Sendable {
    case all, folders, documents, images
    var clause: String? {
        switch self {
        case .all: nil
        case .folders: "kMDItemContentTypeTree == 'public.folder'"
        case .documents: "(kMDItemContentTypeTree == 'public.text' || kMDItemContentTypeTree == 'com.adobe.pdf' || kMDItemContentTypeTree == 'public.composite-content')"
        case .images: "kMDItemContentTypeTree == 'public.image'"
        }
    }
}

public actor LauncherFileSearch {
    public init() {}
    public static func expression(_ text: String, filter: LauncherFileFilter) -> String? {
        let terms = text.prefix(256).split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return nil }
        var clauses = terms.map { term in
            let literal = term.reduce(into: "") { result, c in
                if "\\\"*?".contains(c) { result.append("\\") }
                result.append(c)
            }
            return "kMDItemFSName == \"*\(literal)*\"cd"
        }
        if let clause = filter.clause { clauses.append(clause) }
        return clauses.joined(separator: " && ")
    }
    public static func isWithinRoots(_ url: URL, roots: [URL]) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return roots.contains {
            let root = $0.standardizedFileURL.resolvingSymlinksInPath().path
            return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
        }
    }
    public func search(_ text: String, roots: [URL], filter: LauncherFileFilter) async throws -> [LauncherEntry] {
        try Task.checkCancellation()
        let roots = roots.filter { $0.isFileURL }.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        guard !roots.isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              let expression = Self.expression(text, filter: filter) else { return [] }
        let operation = SpotlightSearchOperation(expression: expression, roots: roots)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await operation.value()
        } onCancel: {
            operation.cancel()
        }
    }
}

/// All query/continuation state belongs to the serial queue. Spotlight gathers asynchronously,
/// leaving the queue free to stop the query immediately when the caller cancels.
private final class SpotlightSearchOperation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.macmanager.launcher-spotlight", qos: .userInitiated)
    private let expression: String
    private let roots: [URL]
    private var query: MDQuery?
    private var continuation: CheckedContinuation<[LauncherEntry], any Error>?
    private var cancelled = false

    init(expression: String, roots: [URL]) {
        self.expression = expression; self.roots = roots
    }

    func value() async throws -> [LauncherEntry] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !cancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                guard let query = MDQueryCreate(nil, expression as CFString, nil, [kMDItemFSName] as CFArray) else {
                    finish(.failure(CocoaError(.fileReadUnknown))); return
                }
                self.query = query
                MDQuerySetSearchScope(query, roots as CFArray, 0)
                MDQuerySetMaxCount(query, 200)
                MDQuerySetDispatchQueue(query, queue)
                CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(),
                    Unmanaged.passUnretained(self).toOpaque(), Self.didFinish,
                    kMDQueryDidFinishNotification, Unmanaged.passUnretained(query).toOpaque(), .deliverImmediately)
                guard MDQueryExecute(query, 0) else {
                    finish(.failure(CocoaError(.fileReadUnknown))); return
                }
                queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.finish(.failure(CocoaError(.fileReadUnknown)))
                }
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            cancelled = true
            finish(.failure(CancellationError()))
        }
    }

    private static let didFinish: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let operation = Unmanaged<SpotlightSearchOperation>.fromOpaque(observer).takeUnretainedValue()
        // Always enqueue to avoid stopping/releasing the query inside its notification callback.
        operation.queue.async { operation.collect() }
    }

    private func collect() {
        guard let query, continuation != nil else { return }
        var results: [LauncherEntry] = []
        let paths = roots.map(\.path)
        for index in 0..<min(MDQueryGetResultCount(query), 200) {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard paths.contains(where: { resolved == $0 || resolved.hasPrefix($0 == "/" ? "/" : $0 + "/") }),
                  !url.pathComponents.contains(where: { $0.hasPrefix(".") || $0.lowercased().hasSuffix(".app") }) else { continue }
            let directory = (MDItemCopyAttribute(item, kMDItemContentType) as? String) == "public.folder"
            results.append(LauncherEntry(id: "file:" + path, title: url.lastPathComponent,
                subtitle: url.deletingLastPathComponent().path, symbol: directory ? "folder" : "doc", action: .file(url)))
            if results.count == 20 { break }
        }
        finish(.success(results))
    }

    private func finish(_ result: Result<[LauncherEntry], any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        if let query {
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetLocalCenter(),
                Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(kMDQueryDidFinishNotification),
                Unmanaged.passUnretained(query).toOpaque())
            MDQueryStop(query)
            self.query = nil
        }
        continuation.resume(with: result)
    }
}
