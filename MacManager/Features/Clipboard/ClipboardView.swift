import AppKit
import MacManagerCore
import SwiftUI

struct ClipboardView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var showingSettings = false
    @State private var confirmingClear = false
    @State private var selected: ClipboardEntry?

    private var service: ClipboardService { state.clipboard }
    private var visibleEntries: [ClipboardEntry] {
        service.entries.filter { query.isEmpty || $0.text?.localizedStandardContains(query) == true }
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
                if visibleEntries.isEmpty {
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
        .sheet(isPresented: $showingSettings) { ClipboardSettingsView().environment(state) }
        .sheet(item: $selected) { entry in
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(state.strings(entry.record.kind == .text ? "clipboard.text" : "clipboard.image")).font(.title2)
                    Spacer()
                    Button(state.strings("clipboard.close")) { selected = nil }
                }
                ScrollView {
                    if let text = entry.text { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    else if let data = entry.thumbnail, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 350)
                    }
                }
                Button(state.strings("clipboard.restore")) {
                    Task { await service.restore(entry.id); selected = nil }
                }
                .buttonStyle(.glassProminent)
            }
            .padding(28).frame(width: 560, height: 430)
        }
        .onChange(of: service.entries.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected.id) { self.selected = nil }
        }
        .onChange(of: service.suspended) { _, suspended in
            if suspended { selected = nil; query = ""; showingSettings = false }
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
            Group {
                if let data = entry.thumbnail, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: entry.record.kind == .text ? "doc.plaintext" : "photo")
                        .font(.title2).foregroundStyle(AppTheme.accent)
                }
            }
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
