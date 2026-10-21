import AppKit
import MacManagerCore
import SwiftUI

// Only visible rows retain decoded images. The shared encrypted repository owns the bounded data cache.
struct ClipboardThumbnailView: View {
    let service: ClipboardService
    let id: UUID
    let kind: ClipboardKind
    var damaged = false
    private struct Request: Equatable { let id: UUID; let kind: ClipboardKind; let suspended: Bool; let damaged: Bool }
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: kind == .image ? "photo" : "doc.plaintext")
                    .font(.title2).foregroundStyle(AppTheme.accent) }
        }
        .task(id: Request(id: id, kind: kind, suspended: service.suspended, damaged: damaged)) {
            image = nil
            guard kind == .image, !damaged, !service.suspended, let data = await service.thumbnail(id), !Task.isCancelled, !service.suspended else { return }
            image = NSImage(data: data)
        }
        .onDisappear { image = nil }
        .onChange(of: service.suspended) { _, suspended in if suspended { image = nil } }
    }
}
