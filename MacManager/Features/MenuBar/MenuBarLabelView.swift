import MacManagerCore
import SwiftUI

struct MenuBarLabelView: View {
    let state: AppState

    private var segments: [MenuBarStatusSegment] {
        MenuBarStatusFormatter.segments(
            preferences: state.preferences.appIntegration.menuBar,
            snapshot: state.metrics.snapshot,
            locale: state.preferences.locale
        )
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "macbook")
            if !segments.isEmpty {
                Text(segments.map(\.text).joined(separator: " / "))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        (["Mac Manager"] + segments.map { segment in
            switch segment.kind {
            case .cpu: "CPU \(segment.text)"
            case .gpu: "GPU \(segment.text)"
            case .memory: "RAM \(segment.text)"
            case .power: "\(state.strings("metric.power.title")) \(segment.text)"
            }
        }).joined(separator: ", ")
    }
}
