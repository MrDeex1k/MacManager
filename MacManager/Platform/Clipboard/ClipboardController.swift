import AppKit
import CryptoKit
import MacManagerCore
import Observation

@MainActor
final class ClipboardController: ApplicationLifecycleParticipant {
    let service: ClipboardService
    private let repository: ClipboardRepository
    private var loop: Task<Void, Never>?
    private var maintenance: Task<Void, Never>?
    private var polling: Task<Void, Never>?
    private let observers = NotificationTokens()
    private let testing: Bool
    private let fixture: Bool
    private var suspendedReasons: Set<String> = []

    init(preferences: PreferencesStore, testing: Bool = false, diagnostics: DiagnosticsStore? = nil) {
        self.testing = testing
        fixture = testing && ProcessInfo.processInfo.arguments.contains("--clipboard-fixture")
        let directory: URL
        let provider: any ClipboardKeyProviding
        let pasteboard: any ClipboardPasteboard
        if testing {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacManagerClipboardUITests-\(UUID().uuidString)")
            provider = EphemeralClipboardKey()
            #if DEBUG
            pasteboard = FixtureClipboardPasteboard(failFirstWrite: ProcessInfo.processInfo.arguments.contains("--clipboard-write-failure"))
            #else
            pasteboard = SystemClipboardPasteboard()
            #endif
        } else {
            let identity = Bundle.main.bundleIdentifier ?? "dev.macmanager.MacManager"
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(identity).appendingPathComponent("Clipboard", isDirectory: true)
            provider = ClipboardKeychain(service: "\(identity).clipboard") { kind in
                Task { @MainActor in diagnostics?.record(.clipboard, kind: kind.rawValue) }
            }
            pasteboard = SystemClipboardPasteboard()
        }
        repository = ClipboardRepository(directory: directory, keys: provider)
        var settings = preferences.clipboard
        if fixture { settings.enabled = true; settings.paused = true }
        service = ClipboardService(preferences: settings, pasteboard: pasteboard, repository: repository,
                                   storageExists: FileManager.default.fileExists(atPath: directory.path),
                                   savePreferences: { preferences.clipboard = $0 })
    }

    func start() {
        guard loop == nil else { return }
        if !testing {
            SystemSessionMonitor.shared.subscribe(in: observers) { [weak self] state in
                guard let self else { return }
                let wasSleeping = self.suspendedReasons.contains("sleep")
                self.suspendedReasons = Set(state.reasons.map { $0 == .sleep ? "sleep" : $0 == .lock ? "lock" : "session" })
                self.scheduleMaintenance()
                Task { @MainActor [weak self] in
                    guard let self, self.loop != nil else { return }
                    if wasSleeping && !state.sleeping { await self.service.maintain() }
                    await self.service.setSuspended(!self.suspendedReasons.isEmpty)
                }
            }
        }
        let clockCenter = NotificationCenter.default
        let clockToken = clockCenter.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleMaintenance() }
        }
        observers.append((clockCenter, clockToken))
        loop = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            if self.fixture {
                if ProcessInfo.processInfo.arguments.contains("--island-dense-clipboard-fixture") {
                    // Exercise a full default history, not just the two visible text cards.
                    for index in 0..<47 {
                        _ = try? await self.repository.insert(ClipboardContent(kind: .text,
                            data: Data(("History item \(index) " + String(repeating: "Long preview text. ", count: 100)).utf8)),
                            preferences: self.service.preferences, now: Date().addingTimeInterval(-Double(index + 1)))
                    }
                }
                _ = try? await self.repository.insert(ClipboardContent(kind: .text, data: Data("Project notes\nLocal clipboard history".utf8)),
                                                  preferences: self.service.preferences, now: Date())
                _ = try? await self.repository.insert(ClipboardContent(kind: .text, data: Data("Zażółć gęślą jaźń".utf8)),
                                                  preferences: self.service.preferences, now: Date().addingTimeInterval(1))
                if ProcessInfo.processInfo.arguments.contains("--island-clipboard-fixture"),
                   let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                    let blue = NSColor(calibratedRed: 0.15, green: 0.45, blue: 1, alpha: 1)
                    for x in 0..<16 { for y in 0..<16 { bitmap.setColor(blue, atX: x, y: y) } }
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        _ = try? await self.repository.insert(ClipboardContent(kind: .image, data: data, thumbnail: data),
                            preferences: self.service.preferences, now: Date().addingTimeInterval(2))
                    }
                }
            }
            await self.service.setSuspended(!self.suspendedReasons.isEmpty)
            guard !Task.isCancelled else { return }
            await self.service.start()
            guard !Task.isCancelled else { return }
            self.watchCaptureState()
            self.watchMaintenance()
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        maintenance?.cancel(); maintenance = nil
        polling?.cancel(); polling = nil
        observers.removeAll()
        service.stop()
    }

    private func watchCaptureState() {
        guard loop != nil else { return }
        polling?.cancel(); polling = nil
        let (capture, seconds) = withObservationTracking {
            (service.preferences.enabled && !service.preferences.paused && !service.suspended,
             service.pollingSeconds)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.watchCaptureState() }
        }
        guard capture else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                self?.service.poll()
                do { try await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(50)) }
                catch { return }
            }
        }
    }

    private func watchMaintenance() {
        guard loop != nil else { return }
        withObservationTracking {
            _ = service.revision
            _ = service.preferences
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.watchMaintenance() }
        }
        scheduleMaintenance()
    }

    private func scheduleMaintenance() {
        guard loop != nil else { return }
        maintenance?.cancel(); maintenance = nil
        guard !suspendedReasons.contains("sleep") else { return }
        maintenance = Task { [weak self] in
            var attemptedDate: Date?
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    guard let date = try await self.service.nextMaintenanceDate() else { return }
                    try Task.checkCancellation()
                    let retryDelay = attemptedDate == date ? 60.0 : 0.0
                    try await Task.sleep(for: .seconds(max(retryDelay, date.timeIntervalSinceNow)), tolerance: .seconds(1))
                    try Task.checkCancellation()
                    attemptedDate = date
                    await self.service.maintain()
                    // If expiry did not advance (including failures while locked), retry slowly.
                } catch is CancellationError { return }
                catch {
                    do { try await Task.sleep(for: .seconds(60), tolerance: .seconds(5)) }
                    catch { return }
                }
            }
        }
    }
}

private struct EphemeralClipboardKey: ClipboardKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}
