import MacManagerCore
import SwiftUI

struct MenuBarLabelView: View {
    @Environment(\.openWindow) private var openWindow
    let state: AppState
    @Environment(\.displayScale) private var displayScale
    @State private var imageCache = MenuBarImageCache()

    private var segments: [MenuBarStatusSegment] {
        MenuBarStatusFormatter.segments(
            preferences: state.preferences.appIntegration.menuBar,
            snapshot: state.metrics.snapshot,
            locale: state.preferences.locale,
            temperatureUnit: state.preferences.temperatureUnit
        )
    }

    var body: some View {
        let segments = segments
        Image(nsImage: segments.isEmpty
              ? (NSImage(systemSymbolName: "macbook", accessibilityDescription: "Mac Manager") ?? NSImage())
              : statusImage(for: segments))
            .accessibilityLabel(accessibilityLabel(for: segments))
            .onAppear { state.launcher.openMainWindow = { openWindow(id: "main") } }
    }

    // MenuBarExtra flattens text labels; a template image preserves both rows
    // and lets macOS apply the correct color for the menu bar background.
    private func statusImage(for segments: [MenuBarStatusSegment]) -> NSImage {
        let language = state.preferences.language.resolvedCode()
        if imageCache.segments == segments, imageCache.language == language,
           imageCache.scale == displayScale, let image = imageCache.image { return image }
        let renderer = ImageRenderer(content:
            HStack(spacing: 8) {
                ForEach(segments) { segment in
                    VStack(spacing: 0) {
                        Text(title(for: segment.kind))
                            .font(.system(size: 8, weight: .semibold))
                        Text(segment.text)
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
            }
            .foregroundStyle(.black)
            .frame(height: 22)
            .fixedSize()
        )
        renderer.scale = displayScale
        let image = renderer.nsImage ?? NSImage()
        image.accessibilityDescription = accessibilityLabel(for: segments)
        image.isTemplate = true
        imageCache.segments = segments; imageCache.language = language
        imageCache.scale = displayScale; imageCache.image = image
        return image
    }

    private func title(for kind: MenuBarSegmentKind) -> String {
        switch kind {
        case .cpu, .cpuTemperature: "CPU"
        case .gpu, .gpuTemperature: "GPU"
        case .memory: "RAM"
        case .power: state.strings("metric.power.title").uppercased()
        case .fans: "RPM"
        }
    }

    private func accessibilityLabel(for segments: [MenuBarStatusSegment]) -> String {
        (["Mac Manager"] + segments.map { segment in
            let label = switch segment.kind {
            case .cpuTemperature: state.strings("menuBar.cpuTemperature")
            case .gpuTemperature: state.strings("menuBar.gpuTemperature")
            case .fans: state.strings("menuBar.fans")
            default: title(for: segment.kind)
            }
            return "\(label) \(segment.text)"
        }).joined(separator: ", ")
    }
}

@MainActor private final class MenuBarImageCache {
    var segments: [MenuBarStatusSegment] = []
    var language = ""
    var scale: CGFloat = 0
    var image: NSImage?
}
