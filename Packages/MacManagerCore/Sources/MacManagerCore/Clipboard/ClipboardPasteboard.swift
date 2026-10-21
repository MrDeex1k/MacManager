import AppKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

public enum ClipboardAccess: Sendable { case allowed, needsPermission, denied }
public enum ClipboardCapture: Sendable {
    case skipped
    case changedDuringRead
    case content(ClipboardRawContent)
    case rejected(ClipboardFailure)
}
public struct ClipboardRawContent: Sendable {
    public let kind: ClipboardKind
    public let data: Data
    public let sourceBundleID: String?
    public init(kind: ClipboardKind, data: Data, sourceBundleID: String? = nil) {
        self.kind = kind; self.data = data; self.sourceBundleID = sourceBundleID
    }
    public func normalized() throws -> ClipboardContent {
        try Task.checkCancellation()
        let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "PointsOfInterest")
        let interval = signposter.beginInterval("ClipboardNormalize", id: signposter.makeSignpostID())
        defer { signposter.endInterval("ClipboardNormalize", interval) }
        if kind == .text {
            let content = ClipboardContent(kind: .text, data: data, sourceBundleID: sourceBundleID)
            guard content.isValid else { throw ClipboardFailure.tooLarge }
            return content
        }
        guard data.count <= 40_000_000 else { throw ClipboardFailure.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw ClipboardFailure.unsupportedImage }
        let w = width.doubleValue, h = height.doubleValue
        guard w.isFinite, h.isFinite, w > 0, h > 0, w * h <= 40_000_000 else { throw ClipboardFailure.tooLarge }
        try Task.checkCancellation()
        func png(_ image: CGImage, maximumBytes: Int) throws -> Data {
            let encoding = signposter.beginInterval("ClipboardEncodePNG", id: signposter.makeSignpostID())
            defer { signposter.endInterval("ClipboardEncodePNG", encoding) }
            guard let data = ImageThumbnail.encodePNG(image, maximumBytes: Int.max) else {
                throw ClipboardFailure.unsupportedImage
            }
            try Task.checkCancellation()
            guard data.count <= maximumBytes else { throw ClipboardFailure.tooLarge }
            return data
        }
        // Keep one full-resolution decode alive at a time. The returned PNG owns
        // its bytes; ImageIO temporaries are released before decoding the preview.
        let full = try autoreleasepool {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(w, h),
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { throw ClipboardFailure.unsupportedImage }
            try Task.checkCancellation()
            return try png(image, maximumBytes: ClipboardContent.maximumImageBytes)
        }
        try Task.checkCancellation()
        let preview = try autoreleasepool {
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { throw ClipboardFailure.unsupportedImage }
            try Task.checkCancellation()
            return try png(thumbnail, maximumBytes: 1_000_000)
        }
        let content = ClipboardContent(kind: .image, data: full, thumbnail: preview, sourceBundleID: sourceBundleID)
        guard content.isValid else { throw ClipboardFailure.tooLarge }
        return content
    }
}

@MainActor
public protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    var access: ClipboardAccess { get }
    func requestAccess()
    func capture(exclusions: Set<String>) -> ClipboardCapture
    func restore(_ content: ClipboardRestoredContent) throws
}

@MainActor
public final class SystemClipboardPasteboard: ClipboardPasteboard {
    public static let restoredType = NSPasteboard.PasteboardType("dev.macmanager.restored-clipboard")
    private let pasteboard: NSPasteboard
    private let foregroundBundleID: () -> String?

    public init(pasteboard: NSPasteboard = .general, foregroundBundleID: @escaping () -> String? = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }) {
        self.pasteboard = pasteboard; self.foregroundBundleID = foregroundBundleID
    }
    public var changeCount: Int { pasteboard.changeCount }
    public var access: ClipboardAccess {
        switch pasteboard.accessBehavior {
        case .alwaysAllow: .allowed
        case .alwaysDeny: .denied
        default: .needsPermission
        }
    }
    public func requestAccess() {
        // Explicit user action only. Discard existing content instead of importing it.
        _ = pasteboard.string(forType: .string)
    }
    public func capture(exclusions: Set<String>) -> ClipboardCapture {
        let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "PointsOfInterest")
        let interval = signposter.beginInterval("ClipboardPasteboardRead", id: signposter.makeSignpostID())
        defer { signposter.endInterval("ClipboardPasteboardRead", interval) }
        guard access == .allowed else { return .skipped }
        let count = pasteboard.changeCount
        let foreground = foregroundBundleID()
        guard foreground.map(exclusions.contains) != true,
              let items = pasteboard.pasteboardItems, items.count == 1, let item = items.first else { return .skipped }
        let types = Set(item.types.map(\.rawValue))
        guard !types.contains(Self.restoredType.rawValue), !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue),
              !ClipboardPrivacy.shouldSkip(types: types, declaredSource: nil, foregroundSource: foreground, exclusions: exclusions) else {
            return .skipped
        }
        let declared = item.string(forType: .init("org.nspasteboard.source"))
        guard !ClipboardPrivacy.shouldSkip(types: types, declaredSource: declared, foregroundSource: foreground, exclusions: exclusions) else {
            return .skipped
        }
        let source = declared?.isEmpty == false ? declared : foreground
        let kind: ClipboardKind
        let data: Data
        if let text = item.data(forType: .string), !text.isEmpty {
            kind = .text
            guard text.count <= ClipboardContent.maximumTextBytes else { return .rejected(.tooLarge) }
            data = text
        } else if item.types.contains(.png) || item.types.contains(.tiff) {
            kind = .image
            guard let image = item.data(forType: item.types.contains(.png) ? .png : .tiff) else { return .skipped }
            guard image.count <= 40_000_000 else { return .rejected(.tooLarge) }
            data = image
        } else {
            return .skipped
        }
        guard count == pasteboard.changeCount else { return .changedDuringRead }
        return .content(ClipboardRawContent(kind: kind, data: data, sourceBundleID: source))
    }
    public func restore(_ content: ClipboardRestoredContent) throws {
        try LocalClipboardWriter(pasteboard: pasteboard).write(content, history: .excludeFromHistory)
    }
}
