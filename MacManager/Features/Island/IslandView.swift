import AppKit
import MacManagerCore
import SwiftUI

struct IslandView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var sectionHighlight
    let coordinator: IslandCoordinator
    var body: some View {
        VStack(alignment: .leading, spacing: coordinator.displayedSection == .clipboard ? 8 : 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    sectionButton(.clipboard, title: coordinator.strings("island.clipboard.tab"))
                    sectionButton(.music, title: coordinator.strings("music.title"))
                }
                .padding(3)
                .glassEffect(.regular.interactive(), in: .capsule)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: coordinator.section)
                Button { coordinator.dismiss(restoreFocus: true) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.red, in: Circle())
                        .contentShape(Circle())
                }
                    .buttonStyle(.plain)
                    .help(coordinator.strings("island.close"))
                    .accessibilityLabel(coordinator.strings("island.close"))
                    .accessibilityIdentifier("island.close")
            }
            Group {
            if coordinator.displayedSection == .clipboard {
              HStack {
                IslandSearchField(coordinator: coordinator).frame(height: 30)
                if !coordinator.query.isEmpty {
                    Button { coordinator.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(coordinator.strings("clipboard.search.clear"))
                        .accessibilityIdentifier("island.search.clear")
                }
            }
              if let model = coordinator.clipboardModel {
                IslandClipboardContent(model: model, strings: coordinator.strings)
              }
            } else if let music = coordinator.music {
                IslandMusicView(service: music, strings: coordinator.strings)
            }
            }
            .opacity(coordinator.sectionOpacity)
            .allowsHitTesting(coordinator.section == coordinator.displayedSection && coordinator.sectionOpacity > 0.5)
            .accessibilityHidden(coordinator.section != coordinator.displayedSection || coordinator.sectionOpacity < 0.5)

        }
        .padding(.horizontal, 30)
        .padding(.bottom, coordinator.displayedSection == .clipboard ? 12 : 22)
        .padding(.top, coordinator.topInset + 18)
        // Lay out the destination once; the window reveals/crops it as it grows.
        // Keep the outer zero-minimum frame so a tall clipboard never shifts the header.
        .frame(height: coordinator.displayedSectionHeight, alignment: .topLeading)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background { IslandBackgroundView() }
    }
    private func sectionButton(_ section: IslandSection, title: String) -> some View {
        Button { coordinator.selectSection(section) } label: {
            Text(title).font(.callout.weight(.medium))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background {
                    if coordinator.section == section {
                        Capsule().fill(.white.opacity(0.16))
                            .matchedGeometryEffect(id: "selection", in: sectionHighlight)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(section == .music ? "island.section.music" : "island.section.clipboard")
        .accessibilityAddTraits(coordinator.section == section ? .isSelected : [])
    }

}

/// The shoulders blend into the top edge; the camera strip contains no controls.
struct IslandSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder: CGFloat = 14
        let radius: CGFloat = 24
        let left = rect.minX + shoulder, right = rect.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + shoulder),
                          control: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: rect.maxY),
                          control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: left + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - radius),
                          control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                          control: CGPoint(x: left, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct IslandSearchField: NSViewRepresentable {
    let coordinator: IslandCoordinator
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.identifier = .init("island.search")
        field.setAccessibilityIdentifier("island.search")
        field.delegate = context.coordinator
        field.isEditable = true; field.isSelectable = true
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        field.placeholderString = coordinator.strings("clipboard.search")
        field.setAccessibilityLabel(coordinator.strings("clipboard.search"))
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
           field.stringValue != coordinator.query { field.stringValue = coordinator.query }
    }
    func makeCoordinator() -> Delegate { Delegate(owner: coordinator) }
    @MainActor final class Delegate: NSObject, NSTextFieldDelegate {
        let owner: IslandCoordinator
        init(owner: IslandCoordinator) { self.owner = owner }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { owner.query = field.stringValue }
        }
    }
}

/// Native glass delegates tint, transparency and accessibility adaptations to macOS.
struct IslandBackgroundView: View {
    var body: some View {
        Color.clear.glassEffect(.regular, in: IslandSilhouette())
            // Keep the native rim, but crop its exterior shadow to the material's silhouette.
            .clipShape(IslandSilhouette())
    }
}
