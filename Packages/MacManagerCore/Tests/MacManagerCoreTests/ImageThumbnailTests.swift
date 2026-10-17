import AppKit
import ImageIO
import Testing
@testable import MacManagerCore

@Test func thumbnailRespectsDimensionsAndBudgets() throws {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 128,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let raw = try #require(bitmap.representation(using: .png, properties: [:]))
    let data = try #require(ImageThumbnail.png(raw))
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 256 && image.height == 64)
    #expect(ImageThumbnail.png(raw, maximumInputBytes: raw.count - 1) == nil)
    #expect(ImageThumbnail.png(raw, maximumOutputBytes: 1) == nil)
    #expect(ImageThumbnail.png(Data([1, 2, 3])) == nil)
}
