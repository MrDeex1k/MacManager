import AppKit
import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppState.self) private var state
    @State private var copied = false

    var body: some View {
        let strings = state.strings
        let report = state.diagnosticReport()
        VStack(alignment: .leading, spacing: 16) {
            Label(strings("diagnostics.title"), systemImage: "stethoscope")
                .font(.headline)
            Text(strings("diagnostics.note"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(report)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.18), in: .rect(cornerRadius: 10))
                .accessibilityIdentifier("diagnostics.report")

            HStack {
                Button(
                    copied ? strings("diagnostics.copied") : strings("diagnostics.copy"),
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                ) {
                    copyReport(report)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("diagnostics.copy")
                Spacer()
                Text(strings("diagnostics.local"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostics.content")
    }

    private func copyReport(_ report: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: [.currentHostOnly])
        copied = pasteboard.setString(report, forType: .string)
    }
}
