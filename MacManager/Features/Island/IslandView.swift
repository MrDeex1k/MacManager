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
                    ForEach(coordinator.availableSections, id: \.self) { section in
                        let index = IslandSection.allCases.firstIndex(of: section)!
                        sectionButton(section, title: coordinator.strings(section.titleKey))
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .option)
                            .help(coordinator.strings(section.titleKey) + " (⌥" + String(index + 1) + ")")
                    }
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
                NativeSearchField(text: coordinator.query, placeholder: coordinator.strings("clipboard.search"),
                                  identifier: "island.search", style: .island) { coordinator.query = $0 }
                    .frame(height: 30)
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
            } else if coordinator.displayedSection == .music, let music = coordinator.music {
                IslandMusicView(service: music, strings: coordinator.strings)
            } else if coordinator.displayedSection == .podcast, let podcasts = coordinator.podcasts {
                IslandMusicView(service: podcasts, strings: coordinator.strings, source: .podcast)
            } else if coordinator.displayedSection == .spotify {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Spotify", systemImage: "music.note").font(.headline)
                    Text(coordinator.strings("spotify.deferred"))
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }.accessibilityIdentifier("spotify.deferred")
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
        .accessibilityIdentifier("island.section." + section.rawValue)
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

/// Native glass delegates tint, transparency and accessibility adaptations to macOS.
struct IslandBackgroundView: View {
    var body: some View {
        Color.clear.glassEffect(.regular, in: IslandSilhouette())
            // Keep the native rim, but crop its exterior shadow to the material's silhouette.
            .clipShape(IslandSilhouette())
    }
}
