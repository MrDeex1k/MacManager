import CryptoKit
import Foundation
import LocalAuthentication
import Security
import OSLog

public protocol ClipboardKeyProviding: Sendable {
    func key(createIfMissing: Bool) throws -> SymmetricKey
}

public enum ClipboardKeyDiagnostic: String, CaseIterable, Sendable {
    case keyMissing, keyAccessDenied, keyTemporarilyUnavailable, keyReadFailed
    case keyEnvelopeInvalid, keyHardwareUnavailable, keyHardwareFailed, keyWriteFailed
}

public struct ClipboardKeychain: ClipboardKeyProviding {
    private struct Envelope: Codable {
        let version: Int
        let enclaveKey: Data
        let peerPublicKey: Data
    }
    private let service: String
    private let diagnostic: @Sendable (ClipboardKeyDiagnostic) -> Void
    public init(service: String, diagnostic: @escaping @Sendable (ClipboardKeyDiagnostic) -> Void = { _ in }) {
        self.service = service; self.diagnostic = diagnostic
    }

    static func readDiagnostic(_ status: OSStatus) -> ClipboardKeyDiagnostic {
        switch status {
        case errSecItemNotFound: .keyMissing
        case errSecAuthFailed, errSecUserCanceled: .keyAccessDenied
        case errSecInteractionNotAllowed, errSecNotAvailable: .keyTemporarilyUnavailable
        default: .keyReadFailed
        }
    }

    public func key(createIfMissing: Bool) throws -> SymmetricKey {
        let signposter = OSSignposter(subsystem: "dev.macmanager.MacManager", category: "PointsOfInterest")
        let interval = signposter.beginInterval("ClipboardReadAndDeriveKey", id: signposter.makeSignpostID())
        defer { signposter.endInterval("ClipboardReadAndDeriveKey", interval) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "clipboard-history-v1",
            kSecAttrSynchronizable as String: false
        ]
        let context = LAContext()
        context.interactionNotAllowed = true
        var read = query
        read[kSecUseAuthenticationContext as String] = context
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return try unlock(data, context: context)
        }
        guard status == errSecItemNotFound, createIfMissing else {
            diagnostic(Self.readDiagnostic(status)); throw ClipboardFailure.keyUnavailable
        }
        guard SecureEnclave.isAvailable,
              let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [], nil) else {
            diagnostic(.keyHardwareUnavailable); throw ClipboardFailure.keyUnavailable
        }
        let data: Data
        do {
            let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access, authenticationContext: context)
            let peer = P256.KeyAgreement.PrivateKey()
            data = try JSONEncoder().encode(Envelope(version: 1, enclaveKey: enclave.dataRepresentation,
                                                    peerPublicKey: peer.publicKey.x963Representation))
        } catch { diagnostic(.keyHardwareFailed); throw ClipboardFailure.keyUnavailable }
        let key = try unlock(data, context: context)
        var insert = query
        // The file-based macOS Keychain stores only the hardware-wrapped envelope.
        // Device binding and lock protection come from Secure Enclave, not ignored Keychain attributes.
        insert[kSecValueData as String] = data
        let result = SecItemAdd(insert as CFDictionary, nil)
        if result == errSecDuplicateItem { return try self.key(createIfMissing: false) }
        guard result == errSecSuccess else { diagnostic(.keyWriteFailed); throw ClipboardFailure.keyUnavailable }
        return key
    }

    private func unlock(_ data: Data, context: LAContext) throws -> SymmetricKey {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1 else { throw ClipboardFailure.keyUnavailable }
        } catch { diagnostic(.keyEnvelopeInvalid); throw ClipboardFailure.keyUnavailable }
        do {
            let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: envelope.enclaveKey,
                                                                         authenticationContext: context)
            let peer = try P256.KeyAgreement.PublicKey(x963Representation: envelope.peerPublicKey)
            let secret = try enclave.sharedSecretFromKeyAgreement(with: peer)
            return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(service.utf8),
                sharedInfo: Data("MacManager.clipboard.AES256.v1".utf8), outputByteCount: 32)
        } catch { diagnostic(.keyHardwareFailed); throw ClipboardFailure.keyUnavailable }
    }
}
