// Adapted from Tinycast FileSearchService/Query, Copyright (C) 2026 Abue Ammar.
// AGPL-3.0-or-later; used under AGPL-3.0. Source: c5cff8cbb9b7e12ac75c058da9573045c76029b7.
// Modified 2026-09-23: explicit roots only, serial bounded queries, no recent-file history.
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
    public func search(_ text: String, roots: [URL], filter: LauncherFileFilter) throws -> [LauncherEntry] {
        try Task.checkCancellation()
        let roots = roots.filter { $0.isFileURL }
        guard !roots.isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
              let expression = Self.expression(text, filter: filter) else { return [] }
        guard let query = MDQueryCreate(nil, expression as CFString, nil, [kMDItemFSName] as CFArray) else {
            throw CocoaError(.fileReadUnknown)
        }
        MDQuerySetSearchScope(query, roots as CFArray, 0)
        MDQuerySetMaxCount(query, 200)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { throw CocoaError(.fileReadUnknown) }
        defer { MDQueryStop(query) }
        var results: [LauncherEntry] = []
        for index in 0..<min(MDQueryGetResultCount(query), 200) {
            try Task.checkCancellation()
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else { continue }
            let url = URL(fileURLWithPath: path)
            guard Self.isWithinRoots(url, roots: roots),
                  !url.pathComponents.contains(where: { $0.hasPrefix(".") || $0.lowercased().hasSuffix(".app") }) else { continue }
            let directory = (MDItemCopyAttribute(item, kMDItemContentType) as? String) == "public.folder"
            results.append(LauncherEntry(id: "file:" + path, title: url.lastPathComponent,
                subtitle: url.deletingLastPathComponent().path, symbol: directory ? "folder" : "doc",
                action: .file(url)))
        }
        return Array(results.prefix(20))
    }
}
