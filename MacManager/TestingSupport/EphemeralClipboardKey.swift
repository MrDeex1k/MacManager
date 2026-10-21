#if DEBUG
import CryptoKit
import MacManagerCore

struct EphemeralClipboardKey: ClipboardKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}
#endif
