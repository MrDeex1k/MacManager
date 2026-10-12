import AppKit
import MacManagerCore
import SwiftUI

struct ClipboardView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var showingSettings = false
    @State private var confirmingClear = false
    @State private var selected: ClipboardEntry?
    @State private var filtered: [ClipboardEntry] = []
    @State private var completedSearch: SearchRequest?
    @State private var searchFailure: ClipboardFailure?

    private struct SearchRequest: Hashable {
        let query: String
        let revision: Int
        let suspended: Bool
    }
    private var searchRequest: SearchRequest {
        SearchRequest(query: query, revision: service.revision, suspended: service.suspended)
    }

    private var service: ClipboardService { state.clipboard }
    private var visibleEntries: [ClipboardEntry] {
        guard !service.suspended else { return [] }
        if query.isEmpty { return service.entries }
        return completedSearch == searchRequest ? filtered : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                PageHeading(title: state.strings("clipboard.title"), subtitle: state.strings("clipboard.subtitle"))
                Button { showingSettings = true } label: {
                    Label(state.strings("clipboard.options"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("clipboard.options")
            }
            HStack(spacing: 16) {
                Label(state.strings("clipboard.status.\(service.status.rawValue)"), systemImage: statusSymbol)
                    .foregroundStyle(service.status == .recording ? AppTheme.accent : .secondary)
                    .accessibilityIdentifier("clipboard.status")
                Spacer()
                if service.preferences.enabled {
                    Button(state.strings(service.preferences.paused ? "clipboard.resume" : "clipboard.pause")) {
                        var preferences = service.preferences
                        preferences.paused.toggle()
                        Task { await service.updatePreferences(preferences) }
                    }
                    .buttonStyle(.glass)
                    .disabled(service.suspended)
                    .accessibilityIdentifier("clipboard.pause")
                } else {
                    Button(state.strings("clipboard.enable")) {
                        var preferences = service.preferences
                        preferences.enabled = true; preferences.paused = false
                        Task { await service.updatePreferences(preferences) }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(service.suspended)
                    .accessibilityIdentifier("clipboard.enable")
                }
            }
            if service.status == .needsPermission || service.status == .denied {
                VStack(alignment: .leading, spacing: 12) {
                    Text(state.strings("clipboard.permission.note")).foregroundStyle(.secondary)
                    HStack {
                        Button(state.strings("clipboard.permission.request")) { service.requestAccess() }
                            .buttonStyle(.glass)
                        Button(state.strings("clipboard.permission.settings")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            if let failure = service.failure {
                HStack {
                    Label(state.strings("clipboard.error.\(failure.rawValue)"), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    if failure == .storage || failure == .keyUnavailable {
                        Button(state.strings("clipboard.retry")) { Task { await service.refresh() } }
                    }
                }
            }
            Divider()
            if !service.suspended {
                HStack(spacing: 16) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(state.strings("clipboard.search"), text: $query)
                            .textFieldStyle(.plain)
                            .accessibilityIdentifier("clipboard.search")
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .accessibilityLabel(state.strings("clipboard.search.clear"))
                        }
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    Text("\(visibleEntries.count)").monospacedDigit().foregroundStyle(.secondary)
                    Button(role: .destructive) { confirmingClear = true } label: {
                        Label(state.strings("clipboard.clear"), systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .disabled(service.entries.isEmpty && service.failure == nil)
                    .accessibilityIdentifier("clipboard.clear")
                }
                if !query.isEmpty && completedSearch != searchRequest {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                } else if !query.isEmpty, completedSearch == searchRequest, let searchFailure {
                    VStack(spacing: 16) {
                        Label(state.strings("clipboard.error.\(searchFailure.rawValue)"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("clipboard.search.failure")
                        Button(state.strings("clipboard.retry")) { Task { await service.refresh() } }
                            .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else if visibleEntries.isEmpty {
                    ContentUnavailableView(state.strings(query.isEmpty ? "clipboard.empty" : "clipboard.noResults"),
                                           systemImage: "clipboard", description: Text(state.strings("clipboard.empty.note")))
                        .frame(minHeight: 180)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleEntries) { entry in
                            row(entry)
                            Divider()
                        }
                    }
                }
            }
        }
        .task(id: searchRequest) {
            guard !Task.isCancelled else { return }
            let request = searchRequest
            searchFailure = nil
            guard !request.suspended, !request.query.isEmpty else {
                filtered = []; completedSearch = nil
                return
            }
            do {
                let matches = try await service.search(request.query)
                try Task.checkCancellation()
                guard request == searchRequest else { return }
                filtered = matches; completedSearch = request
            } catch is CancellationError {
                // Cancelled requests must not overwrite a newer request's state.
            } catch {
                guard !Task.isCancelled, request == searchRequest else { return }
                filtered = []
                searchFailure = error as? ClipboardFailure ?? .storage
                completedSearch = request
            }
        }
        .onDisappear { filtered = []; completedSearch = nil; searchFailure = nil }
        .sheet(isPresented: $showingSettings) { ClipboardSettingsView().environment(state) }
        .sheet(item: $selected) { entry in
            ClipboardDetailView(service: service, entry: entry, strings: state.strings) { selected = nil }
        }
        .onChange(of: service.revision) { _, _ in
            if let selected, !service.entries.contains(where: { $0.id == selected.id }) { self.selected = nil }
        }
        .onChange(of: service.suspended) { _, suspended in
            if suspended { selected = nil; query = ""; showingSettings = false; filtered = [] }
        }
        .alert(state.strings("clipboard.clear.confirm"), isPresented: $confirmingClear) {
            Button(state.strings("clipboard.cancel"), role: .cancel) {}
            Button(state.strings("clipboard.clear"), role: .destructive) { Task { await service.clear() } }
        } message: { Text(state.strings("clipboard.clear.note")) }
    }

    private var statusSymbol: String {
        switch service.status {
        case .recording: "checkmark.circle.fill"
        case .paused: "pause.circle"
        case .locked: "lock"
        case .disabled: "circle"
        default: "exclamationmark.circle"
        }
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 18) {
            ClipboardThumbnailView(service: service, id: entry.id)
                .frame(width: 52, height: 52)
            Button { selected = entry } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.damaged ? state.strings("clipboard.error.damagedEntry") :
                         entry.text.map { String($0.prefix(300)) } ?? state.strings("clipboard.image"))
                        .font(.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(entry.record.capturedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.damaged)
            Button {
                Task { await service.restore(entry.id) }
            } label: {
                Label(state.strings(service.restoredID == entry.id ? "clipboard.restored" : "clipboard.restore"),
                      systemImage: service.restoredID == entry.id ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.glass)
            .disabled(entry.damaged)
            .accessibilityIdentifier("clipboard.restore.\(entry.id)")
            Button(role: .destructive) { Task { await service.delete(entry.id) } } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.strings("clipboard.delete"))
            .accessibilityIdentifier("clipboard.delete.\(entry.id)")
        }
        .padding(.vertical, 16)
    }
}
