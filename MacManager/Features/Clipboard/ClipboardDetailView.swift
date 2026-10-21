import AppKit
import MacManagerCore
import SwiftUI

struct ClipboardDetailView: View {
    let service: ClipboardService
    let entry: ClipboardEntry
    let strings: AppStrings
    let close: () -> Void
    @State private var content: ClipboardRestoredContent?
    @State private var loading = true
    @State private var restoreTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(strings(entry.record.kind == .text ? "clipboard.text" : "clipboard.image")).font(.title2)
                Spacer()
                Button(strings("clipboard.close"), action: close)
            }
            ScrollView {
                if loading { ProgressView() }
                else if let content {
                    if content.kind == .text, let text = String(data: content.data, encoding: .utf8) {
                        Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } else if let image = NSImage(data: content.data) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 350)
                    }
                } else { Text(strings("clipboard.error.damagedEntry")) }
            }
            if let failure = service.failure {
                Label(strings("clipboard.error.\(failure.rawValue)"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).accessibilityIdentifier("clipboard.detail.error")
            }
            Button(strings("clipboard.restore")) {
                restoreTask = Task {
                    let succeeded = await service.restore(entry.id)
                    guard !Task.isCancelled else { return }
                    restoreTask = nil
                    if succeeded { close() }
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(content == nil || restoreTask != nil || service.suspended)
            .accessibilityIdentifier("clipboard.detail.restore")
        }
        .padding(28).frame(width: 560, height: 430)
        .task(id: entry.id) {
            content = await service.content(entry.id)
            if Task.isCancelled || service.suspended { content = nil }
            loading = false
        }
        .onDisappear { restoreTask?.cancel(); restoreTask = nil; content = nil }
        .onChange(of: service.suspended) { _, suspended in if suspended { content = nil; close() } }
    }
}
