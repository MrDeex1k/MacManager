import Charts
import Foundation
import MacManagerCore
import SwiftUI

enum HistoryTimeAxis {
    @AxisContentBuilder static func content(strings: AppStrings, locale: Locale) -> some AxisContent {
        AxisMarks(values: [-300.0, -240, -180, -120, -60, 0]) { mark in
            AxisGridLine().foregroundStyle(.primary.opacity(0.06))
            AxisValueLabel(anchor: mark.as(Double.self) == 0 ? .topTrailing : .topLeading) {
                if let seconds = mark.as(Double.self) {
                    Text(seconds == 0 ? strings("history.now") : String(
                        format: strings("history.minutesAgo"), locale: locale, Int64(-seconds / 60)))
                }
            }
        }
    }
}

struct HistoryChartEmptyState: View {
    let isEmpty: Bool
    let text: String
    let identifier: String
    var body: some View {
        if isEmpty {
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier(identifier)
        }
    }
}
