#if DEBUG
import AppKit
import MacManagerCore

enum ClipboardFixture {
    static func seed(repository: ClipboardRepository, preferences: ClipboardPreferences) async {
        if UITestConfiguration.current.contains("--island-dense-clipboard-fixture") {
            // Exercise a full default history, not just the two visible text cards.
            for index in 0..<47 {
                _ = try? await repository.insert(ClipboardContent(kind: .text,
                    data: Data(("History item \(index) " + String(repeating: "Long preview text. ", count: 100)).utf8)),
                    preferences: preferences, now: Date().addingTimeInterval(-Double(index + 1)))
            }
        }
        _ = try? await repository.insert(ClipboardContent(kind: .text, data: Data("Project notes\nLocal clipboard history".utf8)),
                                          preferences: preferences, now: Date())
        _ = try? await repository.insert(ClipboardContent(kind: .text, data: Data("Zażółć gęślą jaźń".utf8)),
                                          preferences: preferences, now: Date().addingTimeInterval(1))
        if UITestConfiguration.current.contains("--island-clipboard-fixture"),
           let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            let blue = NSColor(calibratedRed: 0.15, green: 0.45, blue: 1, alpha: 1)
            for x in 0..<16 { for y in 0..<16 { bitmap.setColor(blue, atX: x, y: y) } }
            if let data = bitmap.representation(using: .png, properties: [:]) {
                _ = try? await repository.insert(ClipboardContent(kind: .image, data: data, thumbnail: data),
                    preferences: preferences, now: Date().addingTimeInterval(2))
            }
        }
    }
}
#endif
