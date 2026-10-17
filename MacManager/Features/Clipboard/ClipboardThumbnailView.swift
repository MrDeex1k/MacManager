import AppKit
import MacManagerCore
import SwiftUI

// Only visible rows retain decoded images. The shared encrypted repository owns the bounded data cache.
struct ClipboardThumbnailView: View {
    let service: ClipboardService
    let id: UUID
    let kind: ClipboardKind
    private struct Request: Equatable { let id: UUID; let kind: ClipboardKind; let suspended: Bool }
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: kind == .image ? "photo" : "doc.plaintext")
                    .font(.title2).foregroundStyle(AppTheme.accent) }
        }
        .task(id: Request(id: id, kind: kind, suspended: service.suspended)) {
            image = nil
            guard kind == .image, !service.suspended, let data = await service.thumbnail(id), !Task.isCancelled, !service.suspended else { return }
            image = NSImage(data: data)
        }
        .onDisappear { image = nil }
        .onChange(of: service.suspended) { _, suspended in if suspended { image = nil } }
    }
}

struct ClipboardDetailView: View {
    let service: ClipboardService
    let entry: ClipboardEntry
    let strings: AppStrings
    let close: () -> Void
    @State private var content: ClipboardRestoredContent?
    @State private var loading = true

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
            Button(strings("clipboard.restore")) { Task { await service.restore(entry.id); close() } }
                .buttonStyle(.glassProminent).disabled(content == nil)
        }
        .padding(28).frame(width: 560, height: 430)
        .task(id: entry.id) {
            content = await service.content(entry.id)
            if Task.isCancelled || service.suspended { content = nil }
            loading = false
        }
        .onDisappear { content = nil }
        .onChange(of: service.suspended) { _, suspended in if suspended { content = nil; close() } }
    }
}
