import MacManagerCore

/// Moving the chart's time axis does not change its samples. Rebuild only on data changes.
@MainActor final class MetricsChartSeries {
    private var revision: UInt64?
    private var metrics: [MetricKind: [MetricHistoryPoint]] = [:]
    private var sensors: [SensorHistoryKind: [MetricHistoryPoint]] = [:]

    func points(history: MetricsHistory, metric: MetricKind) -> [MetricHistoryPoint] {
        invalidate(history)
        if let points = metrics[metric] { return points }
        let points = history.points(for: metric)
        metrics[metric] = points
        return points
    }

    func points(history: MetricsHistory, sensor: SensorHistoryKind) -> [MetricHistoryPoint] {
        invalidate(history)
        if let points = sensors[sensor] { return points }
        let points = history.points(for: sensor)
        sensors[sensor] = points
        return points
    }

    private func invalidate(_ history: MetricsHistory) {
        guard revision != history.revision else { return }
        revision = history.revision
        metrics.removeAll(keepingCapacity: true)
        sensors.removeAll(keepingCapacity: true)
    }
}
