import AppKit
import ApplicationServices
import Foundation
import ImageIO
import MacManagerCore
import UniformTypeIdentifiers

/// Public Apple Events, serialized away from MainActor. Targets an existing PID, never launches Music.
actor AppleMusicAdapter: MusicPlayerAdapter {
    private var cachedTrack: MusicSnapshot?
    private var cachedPID: pid_t?
    private var artworkAttempt: TimeInterval = 0
    private func code(_ value: String) -> FourCharCode { value.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
    private func target() -> NSAppleEventDescriptor? {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first,
              !application.isTerminated else { return nil }
        if cachedPID != application.processIdentifier { cachedTrack = nil; cachedPID = application.processIdentifier }
        return NSAppleEventDescriptor(processIdentifier: application.processIdentifier)
    }
    private func permission(_ target: NSAppleEventDescriptor, ask: Bool) -> MusicAvailability {
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask) {
        case noErr: .ready
        case -1744: .needsPermission
        case -1743: .denied
        case -600: .notRunning
        default: .unavailable
        }
    }
    func requestAccess() async -> MusicAvailability {
        guard !Task.isCancelled, let target = target() else { return .notRunning }
        return permission(target, ask: true)
    }
    func releaseArtwork() { cachedTrack = nil; artworkAttempt = 0 }

    private func property(_ name: String, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: OSType(typeProperty)), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(.init(enumCode: OSType(formPropertyID)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(.init(typeCode: code(name)), forKeyword: AEKeyword(keyAEKeyData))
        return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))!
    }
    private func artwork(_ track: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: code("cArt")), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(track, forKeyword: AEKeyword(keyAEContainer))
        record.setDescriptor(.init(enumCode: OSType(formAbsolutePosition)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(.init(int32: 1), forKeyword: AEKeyword(keyAEKeyData))
        return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))!
    }
    private func send(_ target: NSAppleEventDescriptor, eventClass: FourCharCode, eventID: FourCharCode,
                      object: NSAppleEventDescriptor? = nil) throws -> NSAppleEventDescriptor {
        try Task.checkCancellation()
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID, targetDescriptor: target,
                                          returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let object { event.setParam(object, forKeyword: AEKeyword(keyDirectObject)) }
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 2)
        try Task.checkCancellation()
        if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        return reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) ?? .null()
    }
    private func get(_ target: NSAppleEventDescriptor, _ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try send(target, eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData), object: object)
    }
    private func availability(_ error: Error) -> MusicAvailability {
        switch (error as NSError).code {
        case -1743: .denied
        case -1744: .needsPermission
        case -1712: .timedOut
        case -600, -609: .notRunning
        default: .unavailable
        }
    }
    func perform(_ command: MusicCommand) async -> MusicAvailability {
        guard !Task.isCancelled, let target = target() else { return .notRunning }
        let access = permission(target, ask: false)
        guard access == .ready else { return access }
        do {
            let id = switch command { case .playPause: "PlPs"; case .previous: "Prev"; case .next: "Next" }
            _ = try send(target, eventClass: code("hook"), eventID: code(id))
            return .ready
        } catch { return availability(error) }
    }
    func read() async -> MusicSnapshot {
        guard !Task.isCancelled, let target = target() else { return MusicSnapshot(availability: .notRunning) }
        let access = permission(target, ask: false)
        guard access == .ready else { return MusicSnapshot(availability: access) }
        do {
            let state = try get(target, property("pPlS")).enumCodeValue
            let playback: MusicPlayback = state == code("kPSP") || state == code("kPSF") || state == code("kPSR") ? .playing : state == code("kPSp") ? .paused : .stopped
            let track: NSAppleEventDescriptor
            do { track = try get(target, property("pTrk")) }
            catch where (error as NSError).code == -1728 || (error as NSError).code == -1700 {
                cachedTrack = nil
                return MusicSnapshot(availability: .ready, playback: playback)
            }
            if track.descriptorType == DescType(typeNull) { cachedTrack = nil; return MusicSnapshot(availability: .ready, playback: playback) }
            let id = try get(target, property("pPIS", of: track)).stringValue ?? ""
            var metadata: MusicSnapshot
            if !id.isEmpty, let cachedTrack, cachedTrack.trackID == id {
                metadata = cachedTrack
                if metadata.artwork == nil, ProcessInfo.processInfo.systemUptime - artworkAttempt >= 15 {
                    artworkAttempt = ProcessInfo.processInfo.systemUptime
                    let raw = try? get(target, property("pRaw", of: artwork(track))).data
                    metadata.artwork = raw.flatMap(Self.thumbnail)
                    self.cachedTrack = metadata
                }
            }
            else {
                let title = try get(target, property("pnam", of: track)).stringValue ?? ""
                let artist = try get(target, property("pArt", of: track)).stringValue ?? ""
                let album = try get(target, property("pAlb", of: track)).stringValue ?? ""
                let duration = try get(target, property("pDur", of: track)).doubleValue
                let raw = try? get(target, property("pRaw", of: artwork(track))).data
                artworkAttempt = ProcessInfo.processInfo.systemUptime
                metadata = MusicSnapshot(availability: .ready, trackID: id.isEmpty ? title : id,
                    title: title, artist: artist, album: album, duration: duration,
                    artwork: raw.flatMap(Self.thumbnail))
                cachedTrack = metadata
            }
            let position = try get(target, property("pPos")).doubleValue
            // A skip during the metadata read must not publish the previous track with a new position.
            let currentID = try get(target, property("pPIS", of: property("pTrk"))).stringValue ?? ""
            guard currentID == id else { cachedTrack = nil; return MusicSnapshot(availability: .idle) }
            return MusicSnapshot(availability: .ready, playback: playback, trackID: metadata.trackID,
                title: metadata.title, artist: metadata.artist, album: metadata.album,
                duration: metadata.duration, position: position, artwork: metadata.artwork)
        } catch { return MusicSnapshot(availability: availability(error)) }
    }
    private static func thumbnail(_ data: Data) -> Data? {
        guard data.count <= 8_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 1_000_000 else { return nil }
        return output as Data
    }
}
