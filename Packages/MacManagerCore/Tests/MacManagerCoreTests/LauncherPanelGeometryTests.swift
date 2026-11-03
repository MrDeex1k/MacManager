import Foundation
import Testing
@testable import MacManagerCore

struct LauncherPanelGeometryTests {
    private let laptop = LauncherPanelGeometry.Display(id: 1,
        frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visibleFrame: CGRect(x: 0, y: 100, width: 1800, height: 1031))
    private let external = LauncherPanelGeometry.Display(id: 2,
        frame: CGRect(x: -2560, y: -133, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -2560, y: -133, width: 2560, height: 1415))

    @Test func openingFollowsPointerAndReconfigurationKeepsDisplayIdentity() {
        let screens = [laptop, external], pointer = CGPoint(x: -1000, y: 500)
        #expect(LauncherPanelGeometry.display(in: screens, preferredID: nil, pointer: pointer)?.id == 2)
        // Moving the pointer to another screen must not move an already open launcher.
        #expect(LauncherPanelGeometry.display(in: screens, preferredID: 1, pointer: pointer)?.id == 1)
        let rearranged = LauncherPanelGeometry.Display(id: 2,
            frame: CGRect(x: 1800, y: 500, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1800, y: 550, width: 1920, height: 1000))
        #expect(LauncherPanelGeometry.display(in: [laptop, rearranged], preferredID: 2, pointer: .zero) == rearranged)
    }

    @Test func disconnectedDisplayFallsBackAndTransientEmptyTopologyHasNoTarget() {
        #expect(LauncherPanelGeometry.display(in: [laptop], preferredID: 2,
            pointer: CGPoint(x: -1000, y: 500)) == laptop)
        #expect(LauncherPanelGeometry.display(in: [], preferredID: 1, pointer: .zero) == nil)
        let invalid = LauncherPanelGeometry.Display(id: 3, frame: .zero, visibleFrame: .zero)
        #expect(LauncherPanelGeometry.display(in: [invalid, laptop], preferredID: 3, pointer: .zero) == laptop)
    }

    @Test(arguments: [
        CGRect(x: 0, y: 100, width: 1800, height: 1031),
        CGRect(x: -2560, y: -133, width: 2560, height: 1415),
        CGRect(x: 1800, y: 1200, width: 1280, height: 695),
        CGRect(x: -500, y: 0, width: 500, height: 400),
        CGRect(x: 100, y: -50, width: 30, height: 20)
    ])
    func panelsStayInsideUsableAreaIncludingDockAndMenuBar(available: CGRect) {
        for expanded in [false, true] {
            let frame = LauncherPanelGeometry.frame(in: available, expanded: expanded)
            #expect(frame.width > 0 && frame.height > 0)
            #expect(available.contains(frame))
            #expect(frame.width <= 680 && frame.height <= (expanded ? 514 : 90))
            #expect(frame.midX == available.midX)
        }
    }

    @Test func scalingAndDockChangesRecomputeBothAxesWithoutCumulativeShrink() {
        let compact = CGRect(x: -1000, y: 40, width: 500, height: 400)
        let full = laptop.visibleFrame
        #expect(LauncherPanelGeometry.frame(in: full, expanded: true).size == CGSize(width: 680, height: 514))
        #expect(LauncherPanelGeometry.frame(in: compact, expanded: true).size == CGSize(width: 460, height: 360))
        // Repeated query updates and a return to the original scale must not retain old bounds.
        for _ in 0..<5 {
            #expect(LauncherPanelGeometry.frame(in: compact, expanded: true).size == CGSize(width: 460, height: 360))
            #expect(LauncherPanelGeometry.frame(in: full, expanded: true).size == CGSize(width: 680, height: 514))
        }
        let collapsed = LauncherPanelGeometry.frame(in: full, expanded: false)
        #expect(collapsed.height == 90)
        #expect(collapsed.maxY == LauncherPanelGeometry.frame(in: full, expanded: true).maxY)
        #expect(LauncherPanelGeometry.frame(in: .zero, expanded: true) == .zero)
    }
}
