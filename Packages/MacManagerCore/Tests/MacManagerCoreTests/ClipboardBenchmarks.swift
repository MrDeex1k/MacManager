import AppKit
import CryptoKit
import Darwin
import Security
import Foundation
import Testing
@testable import MacManagerCore

private func elapsedMilliseconds(_ start: ContinuousClock.Instant) -> Double {
    let value = start.duration(to: .now).components
    return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["MM_BENCHMARKS"] == "1", "Opt-in Release measurements"))
struct ClipboardBenchmarks {
    @Test func imageNormalizationBenchmark() throws {
        for width in [2_048, 6_000] {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let pixels = try #require(bitmap.bitmapData)
            for y in 0..<width {
                for x in 0..<width {
                    let offset = y * bitmap.bytesPerRow + x * 4
                    pixels[offset] = UInt8(truncatingIfNeeded: x)
                    pixels[offset + 1] = UInt8(truncatingIfNeeded: y)
                    pixels[offset + 2] = UInt8(truncatingIfNeeded: x ^ y)
                    pixels[offset + 3] = 255
                }
            }
            for (label, format) in [("PNG", NSBitmapImageRep.FileType.png), ("TIFF", .tiff)] {
                try autoreleasepool {
                let input = try #require(bitmap.representation(using: format, properties: [:]))
                let start = ContinuousClock.now
                do {
                    let content = try ClipboardRawContent(kind: .image, data: input).normalized()
                    #expect(content.isValid)
                    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                    print("Image \(width)x\(width) \(label): inputBytes=\(input.count) outputBytes=\(content.data.count) normalizeMs=\(elapsedMilliseconds(start)) processPeakRSSBytes=\(usage.ru_maxrss)")
                } catch ClipboardFailure.tooLarge {
                    #expect(input.count > 40_000_000)
                    print("Image \(width)x\(width) \(label): inputBytes=\(input.count) rejectedByInputBudgetMs=\(elapsedMilliseconds(start))")
                }
                }
            }
        }
    }

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MM_SYSTEM_TESTS"] == "1", "Uses a named synthetic pasteboard"))
    func pasteboardCaptureBenchmark() throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2_048, pixelsHigh: 2_048,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        memset(try #require(bitmap.bitmapData), 127, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let board = NSPasteboard(name: .init("MacManagerCaptureBenchmark-\(UUID())"))
        defer { board.releaseGlobally() }
        let adapter = SystemClipboardPasteboard(pasteboard: board, foregroundBundleID: { nil })
        for (label, format, type) in [("PNG", NSBitmapImageRep.FileType.png, NSPasteboard.PasteboardType.png), ("TIFF", .tiff, .tiff)] {
            let bytes = try #require(bitmap.representation(using: format, properties: [:]))
            var samples: [Double] = []
            for _ in 0..<10 {
                board.prepareForNewContents(with: .currentHostOnly)
                #expect(board.setData(bytes, forType: type))
                let start = ContinuousClock.now
                guard case .content(let raw) = adapter.capture(exclusions: []) else {
                    Issue.record("Synthetic image capture failed"); return
                }
                samples.append(elapsedMilliseconds(start))
                #expect(raw.data.count == bytes.count)
            }
            samples.sort()
            print("MainActor pasteboard \(label): bytes=\(bytes.count) p50Ms=\(samples[5]) p95Ms=\(samples[9])")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MM_SYSTEM_TESTS"] == "1", "Requires hardware Keychain access"))
    func hardwareKeyDerivationBenchmark() async throws {
        let service = "MacManagerKeyBenchmark-\(UUID())"
        defer {
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                           kSecAttrAccount: "clipboard-history-v1"] as CFDictionary)
        }
        let provider = ClipboardKeychain(service: service)
        _ = try provider.key(createIfMissing: true)
        var samples: [Double] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            _ = try provider.key(createIfMissing: false)
            samples.append(elapsedMilliseconds(start))
        }
        samples.sort()
        print("Hardware key read+derive: calls=20 p50Ms=\(samples[10]) p95Ms=\(samples[19])")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeyWorkload-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let counting = CountingBenchmarkKey(provider: provider)
        let repository = ClipboardRepository(directory: directory, keys: counting)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        memset(try #require(bitmap.bitmapData), 127, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let mutation = try await repository.insert(.init(kind: .image, data: png, thumbnail: png), preferences: .init(), now: Date())
        let id = try #require(mutation.inserted?.id)
        counting.reset()
        _ = try await repository.thumbnail(id)
        print("Photo cold thumbnail key calls=\(counting.count)")
        #expect(counting.count == 1)
        counting.reset()
        _ = try await repository.thumbnail(id)
        print("Photo warm thumbnail key calls=\(counting.count)")
        #expect(counting.count == 0)
        counting.reset()
        _ = try await repository.restore(id, preferences: .init(), now: Date())
        _ = try await repository.restore(id, preferences: .init(), now: Date())
        print("Photo repeated restore key calls=\(counting.count)")
        #expect(counting.count == 2)
    }
}

private final class CountingBenchmarkKey: ClipboardKeyProviding, @unchecked Sendable {
    let provider: ClipboardKeychain
    private let lock = NSLock()
    private var calls = 0
    init(provider: ClipboardKeychain) { self.provider = provider }
    var count: Int { lock.withLock { calls } }
    func reset() { lock.withLock { calls = 0 } }
    func key(createIfMissing: Bool) throws -> SymmetricKey {
        lock.withLock { calls += 1 }
        return try provider.key(createIfMissing: createIfMissing)
    }
}
