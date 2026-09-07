import SwiftUI

struct NetworkView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let strings = state.strings
        VStack(alignment: .leading, spacing: 28) {
            PageHeading(title: strings("network.title"), subtitle: strings("network.subtitle"))
            Surface {
                VStack(spacing: 0) {
                    addressRow(title: strings("network.local"), symbol: "wifi", strings: strings)
                    Divider().padding(.vertical, 22)
                    addressRow(title: strings("network.public"), symbol: "globe", strings: strings)
                }
            }
            Divider()
            Surface {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(AppTheme.accent)
                        .font(.title2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(strings("network.privacy.title")).font(.headline)
                        Text(strings("network.privacy.body"))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(strings("network.notAvailable"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("network.unavailable")
        }
    }

    private func addressRow(title: String, symbol: String, strings: AppStrings) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.headline)
            Spacer()
            Text(strings("value.unavailable"))
                .foregroundStyle(.secondary)
        }
    }
}
