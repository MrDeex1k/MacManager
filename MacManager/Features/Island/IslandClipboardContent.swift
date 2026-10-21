import MacManagerCore
import SwiftUI

struct IslandClipboardContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: IslandClipboardModel
    let strings: AppStrings
    private var service: ClipboardService { model.service }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let failure = model.searchFailure ?? service.failure {
                Label(strings("clipboard.error.\(failure.rawValue)"), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("island.clipboard.error")
            }
            if service.status == .needsPermission || service.status == .denied {
                Button(strings("clipboard.permission.request")) { service.requestAccess() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(!service.preferences.enabled || service.suspended)
                    .accessibilityIdentifier("island.clipboard.permission")
            }
            if model.searching {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.entries.isEmpty {
                Text(strings(model.query.isEmpty ? "clipboard.empty" : "clipboard.noResults"))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("island.clipboard.empty")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(model.entries) { entry in card(entry).id(entry.id) }
                        }
                        .frame(height: 140, alignment: .top)
                        .padding(.vertical, 4)
                        .frame(height: 160, alignment: .top)
                    }
                    .frame(height: 160)
                    .onChange(of: model.selectedID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            HStack(spacing: 8) {
              HStack(spacing: 7) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                Text(strings(model.copiedID == nil ? "clipboard.status.\(service.status.rawValue)" : "island.clipboard.copied"))
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.copiedID)
                    .foregroundStyle(.white.opacity(0.95))
                    .accessibilityIdentifier("island.clipboard.status")
              }
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10).padding(.vertical, 6)
              .background(.white.opacity(0.10), in: Capsule())
                Spacer()
                Button(strings(!service.preferences.enabled ? "clipboard.enable" :
                               service.preferences.paused ? "clipboard.resume" : "clipboard.pause")) {
                    model.toggleCapture()
                }
                .font(.callout).buttonStyle(.bordered).controlSize(.regular)
                .disabled(service.suspended)
                .accessibilityIdentifier("island.clipboard.capture")
            }
            .padding(.top, 2)
        }
        .task(id: model.request) { await model.search(model.request) }
    }

    private var statusSymbol: String {
        if model.copiedID != nil { return "checkmark.circle.fill" }
        switch service.status {
        case .recording: return "record.circle.fill"
        case .paused: return "pause.circle.fill"
        case .disabled: return "stop.circle.fill"
        case .locked: return "lock.fill"
        case .needsPermission, .denied, .unavailable: return "exclamationmark.triangle.fill"
        }
    }
    private var statusColor: Color {
        if model.copiedID != nil { return AppTheme.accent }
        switch service.status {
        case .recording: return AppTheme.accent
        case .paused: return .yellow
        case .needsPermission, .denied, .unavailable: return .orange
        case .disabled, .locked: return .white.opacity(0.8)
        }
    }

    private func card(_ entry: ClipboardEntry) -> some View {
        Button { model.selectedID = entry.id; model.restore(entry.id) } label: {
            cardLabel(entry)
        }
        .buttonStyle(.plain)
        .disabled(entry.damaged || model.restoringID != nil || service.suspended)
        .accessibilityIdentifier("island.clipboard.restore.\(entry.id)")
        .accessibilityLabel(entry.record.kind == .image ? strings("clipboard.image") : entry.text.map { String($0.prefix(200)) } ?? strings("clipboard.text"))
        .accessibilityAddTraits(model.selectedID == entry.id ? .isSelected : [])
        .accessibilityValue(model.copiedID == entry.id ? strings("island.clipboard.copied") : "")
        .help(strings("clipboard.restore"))
        .contextMenu {
            Button(strings("clipboard.delete"), role: .destructive) { model.delete(entry.id) }
                .accessibilityIdentifier("island.clipboard.delete.\(entry.id)")
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.selectedID)
    }
    private func cardLabel(_ entry: ClipboardEntry) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                if entry.record.kind == .image && !entry.damaged {
                    ClipboardThumbnailView(service: service, id: entry.id, kind: entry.record.kind, damaged: entry.damaged)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                } else {
                    Text(entry.damaged ? strings("clipboard.error.damagedEntry") :
                         entry.text.map { String($0.prefix(400)) } ?? strings("clipboard.image"))
                        .font(.callout).lineLimit(7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                HStack(spacing: 5) {
                    Image(systemName: entry.record.kind == .image ? "photo" : "doc.plaintext")
                    Text(strings(entry.record.kind == .image ? "clipboard.image" : "clipboard.text"))
                    Spacer(minLength: 2)
                    if model.restoringID == entry.id { ProgressView().controlSize(.small) }
                    else if model.copiedID == entry.id { Image(systemName: "checkmark").foregroundStyle(AppTheme.accent) }
                    else { Text(entry.record.capturedAt, format: .dateTime.hour().minute()) }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 158, height: 140)
            .background(Color.white.opacity(model.selectedID == entry.id ? 0.12 : 0.055),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                model.selectedID == entry.id ? AppTheme.accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }

}
