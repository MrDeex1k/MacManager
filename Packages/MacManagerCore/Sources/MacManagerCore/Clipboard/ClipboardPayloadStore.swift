import CryptoKit
import Foundation

/// File encoding and authenticated payloads, called only by the repository actor.
struct ClipboardPayloadStore {
    let directory: URL
    private let files = FileManager.default
    func fileURL(_ id: UUID, role: String) -> URL { directory.appendingPathComponent("\(id.uuidString).\(role)") }
    func removeOrphans(records: [ClipboardRecord]) throws {
        let validNames = Set(records.flatMap { [fileURL($0.id, role: "payload").lastPathComponent, fileURL($0.id, role: "preview").lastPathComponent] })
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if ["payload", "preview", "pending"].contains(url.pathExtension), !validNames.contains(url.lastPathComponent) {
                try files.removeItem(at: url)
            }
        }
    }

    func write(_ data: Data, to url: URL) throws {
        let pending = url.appendingPathExtension("pending")
        guard files.createFile(atPath: pending.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw ClipboardFailure.storage
        }
        defer { try? files.removeItem(at: pending) }
        let handle = try FileHandle(forWritingTo: pending)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            try files.moveItem(at: pending, to: url)
        } catch {
            try? handle.close()
            throw error
        }
    }

    func encrypt(_ data: Data, id: UUID, role: String, key: SymmetricKey) throws -> Data {
        guard let result = try AES.GCM.seal(data, using: key, authenticating: Data("\(id.uuidString):\(role):1".utf8)).combined else {
            throw ClipboardFailure.storage
        }
        return result
    }

    func decrypt(_ id: UUID, role: String, key: SymmetricKey, maximumBytes: Int) throws -> Data {
        do {
            let url = fileURL(id, role: role)
            let attributes = try files.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes,
                  attributes[.type] as? FileAttributeType == .typeRegular else { throw ClipboardFailure.damagedEntry }
            let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
            return try AES.GCM.open(sealed, using: key, authenticating: Data("\(id.uuidString):\(role):1".utf8))
        } catch { throw ClipboardFailure.damagedEntry }
    }

}
