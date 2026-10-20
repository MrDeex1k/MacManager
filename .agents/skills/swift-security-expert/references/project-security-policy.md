# MacManager security policy for these references

This project-specific policy governs how the imported security examples are applied. Explicit user instructions take precedence. Read the current implementation and build/entitlement settings before judging a design.

## Storage boundaries

The clipboard currently uses SQLite and encrypted payloads, with a CryptoKit Secure Enclave P256 key-agreement envelope persisted through `ClipboardKeychain`. Its file-based Keychain storage choice is documented in that implementation. Distinguish a raw secret from an opaque hardware-wrapped envelope, and distinguish envelope storage from the SecAccessControl policy enforced by the enclave key.

Choose a Keychain backend based on the actual attributes, signing, entitlements, deployment, and required protection semantics. Data protection Keychain examples apply when that backend is intentionally selected; omission of `kSecUseDataProtectionKeychain` is not by itself a finding. Changing the backend can hide existing items and needs a migration with verified readback and decryptability. Likewise, `kSecAttrAccessible` and `kSecAttrAccessControl` are not interchangeable universal dictionary requirements; validate which API/backend consumes each attribute.

## Data preservation

A missing UserDefaults flag does not prove that keys are stale or that deletion is safe. Never delete Keychain items at startup merely because preferences are absent. Preserve existing keys and ciphertext during lock/unlock, reinstall, preferences reset, upgrade, and transient access failures.

Cleanup belongs to an explicitly requested data reset or a verified migration with a defined retention/rollback policy. Scope any authorized deletion to the exact item class, service/account or key tag, and intended backend/access group. Never use class-only deletion, wildcard synchronizable deletion, or broad shared-group cleanup.

For create-once encryption keys, handle `errSecDuplicateItem` by re-reading the winning existing item; blindly updating it can orphan ciphertext. Credential replacement may use add-or-update when replacement is actually intended. Handle relevant OSStatus results without treating temporary inaccessibility as absence.

## Execution and review

Keep blocking Keychain work off the UI execution path; choose actors, queues, or existing synchronization according to the target's concurrency settings. Preserve justified C/framework interop.

Use Keychain-bound access control when protecting a secret with user authentication. Evaluate LAContext-only UI checks according to the asset they protect; they are not universally a credential-storage vulnerability.

Use authenticated encryption, unique nonces per key, and context/key separation. A random-nonce constructor or a non-security digest is a search lead, not proof of vulnerability. Demonstrate misuse before assigning severity.

The app controls external Music/Podcasts players and performs bounded network requests; it is not assumed to implement accounts, OAuth, cloud sync, certificate pinning, or a backend. Load those reference branches only for actual features.
