import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared encoding with explicit budgets. Callers own content validation and cache lifetime.
public enum ImageThumbnail {
    public static func png(_ data: Data, maximumPixelSize: Int = 256,
                           maximumInputBytes: Int = 8_000_000, maximumOutputBytes: Int = 1_000_000) -> Data? {
        guard !Task.isCancelled, maximumPixelSize > 0, data.count <= maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return encodePNG(image, maximumBytes: maximumOutputBytes)
    }

    public static func encodePNG(_ image: CGImage, maximumBytes: Int) -> Data? {
        guard !Task.isCancelled, maximumBytes > 0 else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), !Task.isCancelled, output.length <= maximumBytes else { return nil }
        return output as Data
    }
}
