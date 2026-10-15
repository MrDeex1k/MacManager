import AppKit
import MacManagerCore
import SwiftUI

struct IslandMusicView: View {
    let service: MusicService
    let strings: AppStrings
    private var snapshot: MusicSnapshot { service.snapshot }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                MusicArtworkView(snapshot: snapshot).frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.title.isEmpty ? strings("music.noTrack") : snapshot.title)
                        .font(.headline).lineLimit(2).accessibilityIdentifier("music.track")
                    if snapshot.availability == .ready {
                        Text(snapshot.artist.isEmpty ? strings("music.unknownArtist") : snapshot.artist)
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        if !snapshot.album.isEmpty { Text(snapshot.album).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    } else {
                        Text(strings("music.status.\(snapshot.availability.rawValue)"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            .accessibilityIdentifier("music.status")
                    }
                    Text("Apple Music").font(.caption2).foregroundStyle(AppTheme.accent)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 10) {
                    HStack(spacing: 0) {
                        control("backward.end.fill", label: "music.previous", command: .previous)
                        Spacer(minLength: 0)
                        control(snapshot.playback == .playing ? "pause.fill" : "play.fill",
                                label: snapshot.playback == .playing ? "music.pause" : "music.play", command: .playPause)
                        Spacer(minLength: 0)
                        control("forward.end.fill", label: "music.next", command: .next)
                    }.font(.title2)
                    if let duration = snapshot.duration, let position = snapshot.position {
                        ProgressView(value: position, total: duration).tint(.white)
                            .accessibilityLabel(strings("music.progress"))
                            .accessibilityValue("\(time(position)) / \(time(duration))")
                        HStack { Text(time(position)); Spacer(); Text("−" + time(max(0, duration - position))) }
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }.frame(width: 234)
            }
            Spacer(minLength: 0)
            HStack {
                if snapshot.availability == .notRunning {
                    Button(strings("music.open")) {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init())
                        }
                    }.accessibilityIdentifier("music.open")
                } else if snapshot.availability == .needsPermission {
                    Button(strings("music.connect")) { service.requestAccess() }
                        .accessibilityIdentifier("music.connect")
                } else if snapshot.availability == .denied {
                    Button(strings("music.permissions")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
                    }.accessibilityIdentifier("music.permissions")
                }
                Spacer()
                if service.busy { ProgressView().controlSize(.small) }
                else { Button(strings("music.refresh")) { service.refresh() }.accessibilityIdentifier("music.refresh") }
            }
            .font(.callout)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(service.busy)
        }
    }
    private func control(_ symbol: String, label: String, command: MusicCommand) -> some View {
        Button { service.perform(command) } label: { Image(systemName: symbol).frame(width: 36, height: 32) }
            .buttonStyle(.plain).accessibilityLabel(strings(label)).accessibilityIdentifier(label)
            .disabled(service.busy || snapshot.availability != .ready || (command != .playPause && snapshot.trackID == nil))
    }
    private func time(_ value: Double) -> String {
        let seconds = Int(min(max(0, value), 86_400 * 365))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct MusicArtworkView: View {
    let snapshot: MusicSnapshot
    @State private var image: NSImage?
    private struct Request: Hashable { let id: String?; let hasArtwork: Bool }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "music.note").font(.system(size: 32)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.08)) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
        .task(id: Request(id: snapshot.trackID, hasArtwork: snapshot.artwork != nil)) {
            image = nil
            if let data = snapshot.artwork, !Task.isCancelled { image = NSImage(data: data) }
        }
        .onDisappear { image = nil }
    }
}
