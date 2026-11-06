import AppKit
import MacManagerCore
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ClipboardPreferences()
    @State private var removalCount = 0
    @State private var confirming = false
    @State private var error = false
    @State private var saving = false
    @State private var proposedPreferences: ClipboardPreferences?
    @State private var saveTask: Task<Void, Never>?

    /// Keeps edits in a local draft and disables the sheet while a retention check or save is pending.
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(state.strings("clipboard.options")).font(.title2.weight(.semibold))
            Toggle(state.strings("clipboard.enabled"), isOn: $draft.enabled)
                .accessibilityIdentifier("clipboard.settings.enabled")
            Divider()
            Text(state.strings("clipboard.retention")).font(.headline)
            HStack {
                limit("clipboard.limit.count", value: $draft.maximumCount, id: "count")
                limit("clipboard.limit.days", value: $draft.maximumDays, id: "days")
                limit("clipboard.limit.megabytes", value: $draft.maximumMegabytes, id: "megabytes")
            }
            Text(state.strings("clipboard.retention.note")).font(.callout).foregroundStyle(.secondary)
            if !draft.isValid { Text(state.strings("clipboard.limits.invalid")).foregroundStyle(.orange) }
            Divider()
            HStack {
                Text(state.strings("clipboard.exclusions")).font(.headline)
                Spacer()
                Button(state.strings("clipboard.addApp")) { addApplication() }.buttonStyle(.glass)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if draft.excludedBundleIDs.isEmpty {
                        Text(state.strings("clipboard.exclusions.empty")).foregroundStyle(.secondary)
                    }
                    ForEach(draft.excludedBundleIDs.sorted(), id: \.self) { id in
                        HStack {
                            Text(id).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { draft.excludedBundleIDs.remove(id) } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel(state.strings("clipboard.removeApp") + " " + id)
                        }
                    }
                }
            }
            .frame(height: 100)
            Text(state.strings("clipboard.privacy.note")).font(.callout).foregroundStyle(.secondary)
            Text(String(format: state.strings("clipboard.databaseSize"), locale: state.preferences.locale,
                        Double(state.clipboard.databaseBytes) / 1_000_000))
                .font(.caption).foregroundStyle(.secondary)
            if error { Text(state.strings("clipboard.error.storage")).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button(state.strings("clipboard.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(state.strings("clipboard.save")) { prepareSave() }
                    .buttonStyle(.glassProminent)
                    .disabled(!draft.isValid || saving)
                    .accessibilityIdentifier("clipboard.settings.save")
            }
        }
        .disabled(saving)
        .padding(28).frame(width: 560)
        .onAppear { draft = state.clipboard.preferences }
        .onDisappear { saveTask?.cancel(); saveTask = nil }
        .alert(state.strings("clipboard.retention.confirm"), isPresented: $confirming) {
            Button(state.strings("clipboard.cancel"), role: .cancel) { proposedPreferences = nil }
            Button(state.strings("clipboard.save"), role: .destructive) {
                if let proposedPreferences { save(proposedPreferences) }
            }
                .accessibilityIdentifier("clipboard.retention.confirm")
        } message: { Text(String(format: state.strings("clipboard.retention.removals"), removalCount)) }
    }

    private func limit(_ key: String, value: Binding<Int>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.strings(key)).font(.callout)
            TextField(state.strings(key), value: value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("clipboard.limit.\(id)")
        }
    }
    private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier { draft.excludedBundleIDs.insert(id) }
            }
        }
    }
    /// Counts removals for a snapshot of the draft so confirmation applies to the exact settings checked.
    private func prepareSave() {
        guard draft.isValid, !saving else { return }
        let proposed = draft
        proposedPreferences = proposed
        error = false
        saving = true
        saveTask = Task {
            do {
                let count = try await state.clipboard.removalCount(for: proposed)
                guard !Task.isCancelled else { return }
                removalCount = count
                saving = false
                if removalCount > 0 { confirming = true } else { save(proposed) }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = true; saving = false
            }
        }
    }
    /// Applies the checked proposal and dismisses the sheet if its save task is still active.
    private func save(_ proposed: ClipboardPreferences) {
        saving = true
        saveTask = Task {
            guard !Task.isCancelled else { return }
            await state.clipboard.updatePreferences(proposed)
            guard !Task.isCancelled else { return }
            saving = false; dismiss()
        }
    }
}
