#if DEBUG && MM_RESERVED_REGION_PROBE
import AppKit
import SwiftUI

/// Diagnostic values only: no user content, opaque region identifiers or display identifiers.
struct IslandReservedRegionSample: Codable, Equatable {
    struct Insets: Codable, Equatable {
        let top: CGFloat
        let leading: CGFloat
        let bottom: CGFloat
        let trailing: CGFloat
        init(_ insets: EdgeInsets) {
            top = insets.top; leading = insets.leading; bottom = insets.bottom; trailing = insets.trailing
        }
    }
    struct Region: Codable, Equatable {
        let kind: String
        let frame: CGRect
        let margins: Insets
        let active: Bool
    }
    let size: CGSize
    let ignoresSafeArea: Bool
    let frameInRoot: CGRect
    let safeArea: Insets
    let activeOcclusions: Int
    let activeDivisions: Int
    let regions: [Region]
}

@available(macOS 27.1, *)
struct IslandReservedRegionProbe: View {
    let visible: Bool
    let report: (IslandReservedRegionSample) -> Void
    private var ignoresSafeArea: Bool { UITestConfiguration.current.contains("--island-reserved-region-ignore-safe-area") }
    var body: some View {
        GeometryReader { proxy in
            let occlusions = proxy.reservedRegions(kind: .occlusion, options: .includeInactive,
                                                   layoutDirectionBehavior: .fixed)
            let divisions = proxy.reservedRegions(kind: .division, options: .includeInactive,
                                                  layoutDirectionBehavior: .fixed)
            let sample = IslandReservedRegionSample(size: proxy.size, ignoresSafeArea: ignoresSafeArea,
                frameInRoot: proxy.frame(in: .global), safeArea: .init(proxy.safeAreaInsets),
                activeOcclusions: proxy.reservedRegions(kind: .occlusion).count,
                activeDivisions: proxy.reservedRegions(kind: .division).count,
                regions: occlusions.map { .init(kind: "occlusion", frame: $0.frame, margins: .init($0.margins), active: $0.isActive) } +
                    divisions.map { .init(kind: "division", frame: $0.frame, margins: .init($0.margins), active: $0.isActive) })
            Color.clear
                .onChange(of: sample, initial: true) { _, value in if visible { report(value) } }
                // Initial hosting layout can happen before the NSPanel is ordered front.
                .onChange(of: visible) { _, value in if value { report(sample) } }
        }
        .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct IslandReservedRegionReport: Codable {
    let section: String
    let builtIn: Bool
    let panelFrame: CGRect
    let legacyTopInset: CGFloat
    /// Expected camera rectangle in the probe's top-left, unmirrored local coordinates.
    let legacyCameraFrame: CGRect?
    let cameraComparison: String
    let sample: IslandReservedRegionSample

    @MainActor init(section: String, screen: NSScreen, panelFrame: CGRect, topInset: CGFloat,
                    sample: IslandReservedRegionSample) {
        self.section = section; self.panelFrame = panelFrame
        legacyTopInset = topInset; self.sample = sample
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        builtIn = number.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0, right.minX > left.maxX {
            legacyCameraFrame = CGRect(x: left.maxX - panelFrame.minX - sample.frameInRoot.minX,
                y: panelFrame.maxY - screen.frame.maxY - sample.frameInRoot.minY,
                width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
        } else { legacyCameraFrame = nil }
        if let camera = legacyCameraFrame {
            let active = sample.regions.filter { $0.kind == "occlusion" && $0.active }
            if active.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(camera) }) {
                cameraComparison = "covered"
            } else { cameraComparison = active.isEmpty ? "not-reported" : "different" }
        } else { cameraComparison = "no-camera" }
    }

    var json: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "encoding-failed" }
        return text
    }
}
#endif
