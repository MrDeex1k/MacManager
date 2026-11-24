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
        try? encodeBoundedPNG(image, maximumBytes: maximumBytes)
    }

    enum EncodingFailure: Error { case invalidImage, exceedsBudget }

    private final class PNGOutput {
        var data = Data()
        var exceededBudget = false
        let limit: Int

        init(limit: Int) { self.limit = limit }
    }

    static func encodeBoundedPNG(_ image: CGImage, maximumBytes: Int) throws -> Data {
        try Task.checkCancellation()
        guard maximumBytes > 0 else { throw EncodingFailure.exceedsBudget }
        let output = PNGOutput(limit: maximumBytes)
        // Finalization writes synchronously. Keep the context alive through the consumer.
        var callbacks = CGDataConsumerCallbacks(putBytes: { info, bytes, count in
            guard let info, !Task.isCancelled else { return 0 }
            let output = Unmanaged<PNGOutput>.fromOpaque(info).takeUnretainedValue()
            guard !output.exceededBudget, count <= output.limit - output.data.count else {
                output.exceededBudget = true
                return 0
            }
            output.data.append(bytes.assumingMemoryBound(to: UInt8.self), count: count)
            return count
        }, releaseConsumer: nil)
        defer { withExtendedLifetime(output) {} }
        guard let consumer = CGDataConsumer(info: Unmanaged.passUnretained(output).toOpaque(), cbks: &callbacks),
              let destination = CGImageDestinationCreateWithDataConsumer(consumer, UTType.png.identifier as CFString, 1, nil)
        else { throw EncodingFailure.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        let succeeded = CGImageDestinationFinalize(destination)
        try Task.checkCancellation()
        if output.exceededBudget { throw EncodingFailure.exceedsBudget }
        guard succeeded else { throw EncodingFailure.invalidImage }
        return output.data
    }
}
